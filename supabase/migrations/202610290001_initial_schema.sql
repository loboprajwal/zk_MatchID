-- Approved Identity / Wallet model for the MatchID app. Sensitive credential
-- contents and face embeddings remain encrypted on-device; the backend stores
-- only minimal derived claims, status, and salted/peppered fingerprints.
create extension if not exists pgcrypto with schema extensions;

create type public.user_role as enum ('holder', 'verifier', 'admin');
create type public.doc_type as enum ('aadhaar', 'voter_id', 'passport', 'college', 'other');
create type public.cred_status as enum ('valid', 'pending', 'revoked', 'expired');
create type public.proof_result as enum ('pass', 'fail');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  role public.user_role not null default 'holder',
  created_at timestamptz not null default now()
);

create table public.identities (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references public.profiles(id) on delete cascade,
  phone_hash text not null unique check (phone_hash ~ '^[a-f0-9]{64}$'),
  verified_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.wallets (
  id uuid primary key default gen_random_uuid(),
  identity_id uuid not null references public.identities(id) on delete cascade,
  name_masked text not null check (length(name_masked) between 1 and 80),
  name_encrypted text not null,
  created_at timestamptz not null default now(),
  unique (identity_id, name_masked)
);

create table public.credentials (
  id uuid primary key default gen_random_uuid(),
  wallet_id uuid not null references public.wallets(id) on delete cascade,
  doc_type public.doc_type not null,
  issuer text not null,
  doc_fingerprint text not null unique check (doc_fingerprint ~ '^[a-f0-9]{64}$'),
  claims jsonb not null default '{}'::jsonb check (jsonb_typeof(claims) = 'object'),
  status public.cred_status not null default 'pending',
  issued_at timestamptz not null default now(),
  expires_at timestamptz
);

create table public.trusted_issuers (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  public_key text not null,
  is_simulated boolean not null default false,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.verification_requests (
  id uuid primary key default gen_random_uuid(),
  verifier_id uuid not null references public.profiles(id) on delete restrict,
  predicate text not null check (predicate in ('age_18', 'age_21', 'address_verified', 'region_membership', 'degree', 'name_match', 'income_threshold', 'student_status')),
  trusted_issuers uuid[] not null default '{}',
  nonce_hash text not null unique check (nonce_hash ~ '^[a-f0-9]{64}$'),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null
);

create table public.proofs (
  id uuid primary key default gen_random_uuid(),
  credential_id uuid not null references public.credentials(id) on delete restrict,
  request_id uuid references public.verification_requests(id) on delete restrict,
  predicate text not null,
  nonce text not null unique check (length(nonce) between 32 and 256),
  signature text not null,
  expires_at timestamptz not null,
  used_at timestamptz,
  result public.proof_result
);

create table public.otp_attempts (
  phone_hash text primary key check (phone_hash ~ '^[a-f0-9]{64}$'),
  attempts integer not null default 0 check (attempts between 0 and 5),
  locked_until timestamptz,
  updated_at timestamptz not null default now()
);

create table public.audit_log (
  id bigint generated always as identity primary key,
  actor_id uuid references public.profiles(id) on delete set null,
  action text not null,
  entity text not null,
  outcome text not null check (outcome in ('success', 'failure', 'denied')),
  meta jsonb not null default '{}'::jsonb check (jsonb_typeof(meta) = 'object'),
  created_at timestamptz not null default now()
);

create index identities_phone_hash_idx on public.identities(phone_hash);
create index wallets_identity_id_idx on public.wallets(identity_id);
create index credentials_wallet_id_idx on public.credentials(wallet_id);
create index credentials_status_expiry_idx on public.credentials(status, expires_at);
create index verification_requests_verifier_id_idx on public.verification_requests(verifier_id);
create index verification_requests_nonce_hash_idx on public.verification_requests(nonce_hash);
create index proofs_credential_id_idx on public.proofs(credential_id);
create index proofs_request_id_idx on public.proofs(request_id);
create index proofs_nonce_idx on public.proofs(nonce);
create index audit_log_actor_created_idx on public.audit_log(actor_id, created_at desc);

create function public.current_app_role()
returns public.user_role
language sql stable security definer
set search_path = ''
as $$ select role from public.profiles where id = (select auth.uid()) $$;

create function public.is_admin()
returns boolean
language sql stable security definer
set search_path = ''
as $$ select coalesce(public.current_app_role() = 'admin'::public.user_role, false) $$;

create function public.owns_identity(target_identity uuid)
returns boolean
language sql stable security definer
set search_path = ''
as $$ select exists (select 1 from public.identities where id = target_identity and user_id = (select auth.uid())) $$;

create function public.owns_wallet(target_wallet uuid)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.wallets w
    join public.identities i on i.id = w.identity_id
    where w.id = target_wallet and i.user_id = (select auth.uid())
  )
$$;

create function public.provision_profile()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles(id, role) values (new.id, 'holder') on conflict (id) do nothing;
  return new;
end;
$$;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.provision_profile();

-- OTP and proof state transitions run through security-definer RPCs invoked
-- only by Edge Functions using the service role. The client has no table grants.
create function public.reserve_otp_attempt(p_phone_hash text)
returns table(allowed boolean, attempts integer, locked_until timestamptz)
language plpgsql security definer set search_path = '' as $$
declare row_state public.otp_attempts%rowtype;
begin
  if p_phone_hash !~ '^[a-f0-9]{64}$' then raise exception 'invalid_phone_hash'; end if;
  insert into public.otp_attempts(phone_hash, updated_at)
    values (p_phone_hash, now() - interval '30 seconds') on conflict do nothing;
  select * into row_state from public.otp_attempts where phone_hash = p_phone_hash for update;
  if row_state.locked_until is not null and row_state.locked_until > now() then
    return query select false, row_state.attempts, row_state.locked_until; return;
  end if;
  if row_state.locked_until is not null then
    update public.otp_attempts set attempts = 0, locked_until = null, updated_at = now()
      where phone_hash = p_phone_hash returning * into row_state;
  end if;
  if row_state.attempts >= 5 then
    update public.otp_attempts set locked_until = now() + interval '5 minutes', updated_at = now()
      where phone_hash = p_phone_hash returning * into row_state;
    return query select false, row_state.attempts, row_state.locked_until; return;
  end if;
  update public.otp_attempts set attempts = attempts + 1, updated_at = now()
    where phone_hash = p_phone_hash returning * into row_state;
  if row_state.attempts >= 5 then
    update public.otp_attempts set locked_until = now() + interval '5 minutes'
      where phone_hash = p_phone_hash returning * into row_state;
  end if;
  return query select true, row_state.attempts, row_state.locked_until;
end;
$$;

create function public.can_send_otp(p_phone_hash text)
returns table(allowed boolean, reason text, locked_until timestamptz)
language plpgsql security definer set search_path = '' as $$
declare row_state public.otp_attempts%rowtype;
begin
  if p_phone_hash !~ '^[a-f0-9]{64}$' then raise exception 'invalid_phone_hash'; end if;
  insert into public.otp_attempts(phone_hash, updated_at)
    values (p_phone_hash, now() - interval '30 seconds') on conflict do nothing;
  select * into row_state from public.otp_attempts where phone_hash = p_phone_hash for update;
  if row_state.locked_until is not null and row_state.locked_until > now() then
    return query select false, 'otp_locked'::text, row_state.locked_until; return;
  end if;
  if row_state.locked_until is not null then
    update public.otp_attempts set attempts = 0, locked_until = null, updated_at = now()
      where phone_hash = p_phone_hash returning * into row_state;
  end if;
  if row_state.attempts >= 5 then
    update public.otp_attempts set locked_until = now() + interval '5 minutes', updated_at = now()
      where phone_hash = p_phone_hash returning * into row_state;
    return query select false, 'otp_locked'::text, row_state.locked_until; return;
  end if;
  if row_state.updated_at > now() - interval '30 seconds' then
    return query select false, 'resend_cooldown'::text, null::timestamptz; return;
  end if;
  update public.otp_attempts set updated_at = now() where phone_hash = p_phone_hash;
  return query select true, null::text, null::timestamptz;
end;
$$;

create function public.reset_otp_attempts(p_phone_hash text)
returns void language sql security definer set search_path = '' as $$
  update public.otp_attempts set attempts = 0, locked_until = null, updated_at = now()
  where phone_hash = p_phone_hash
$$;

create function public.consume_proof_nonce(p_nonce text, p_signature text)
returns table(consumed boolean, proof_id uuid, credential_id uuid, predicate text)
language plpgsql security definer set search_path = '' as $$
begin
  return query
    update public.proofs p
    set used_at = now(), result = 'pass'::public.proof_result
    where p.nonce = p_nonce and p.signature = p_signature
      and p.used_at is null and p.expires_at > now()
    returning true, p.id, p.credential_id, p.predicate;
  if not found then return query select false, null::uuid, null::uuid, null::text; end if;
end;
$$;

alter table public.profiles enable row level security;
alter table public.identities enable row level security;
alter table public.wallets enable row level security;
alter table public.credentials enable row level security;
alter table public.trusted_issuers enable row level security;
alter table public.verification_requests enable row level security;
alter table public.proofs enable row level security;
alter table public.otp_attempts enable row level security;
alter table public.audit_log enable row level security;

create policy "profiles read own or admin" on public.profiles for select to authenticated
using (id = (select auth.uid()) or public.is_admin());
-- No client INSERT/UPDATE/DELETE policy on profiles: role cannot be self-promoted.

create policy "identity owner read" on public.identities for select to authenticated
using (user_id = (select auth.uid()) or public.is_admin());
-- Identity rows and verified phone hashes are written only by the OTP Edge
-- Function using the service role; clients cannot forge a verification.

create policy "wallet owner read" on public.wallets for select to authenticated
using (public.owns_identity(identity_id) or public.is_admin());
create policy "wallet owner insert" on public.wallets for insert to authenticated
with check (public.owns_identity(identity_id) and public.current_app_role() = 'holder');
create policy "wallet owner update" on public.wallets for update to authenticated
using (public.owns_identity(identity_id)) with check (public.owns_identity(identity_id));
create policy "wallet owner delete" on public.wallets for delete to authenticated
using (public.owns_identity(identity_id));

create policy "credential wallet owner read" on public.credentials for select to authenticated
using (public.owns_wallet(wallet_id) or public.is_admin());
create policy "credential wallet owner insert" on public.credentials for insert to authenticated
with check (
  public.owns_wallet(wallet_id) and
  public.current_app_role() = 'holder' and
  status = 'pending'::public.cred_status
);
-- Clients may register only pending records. Trusted validation functions
-- promote valid/revoked state using the service role; no client status update.
create policy "credential wallet owner delete" on public.credentials for delete to authenticated
using (public.owns_wallet(wallet_id));

create policy "active issuers visible" on public.trusted_issuers for select to authenticated
using (active or public.is_admin());
create policy "admin manages issuers" on public.trusted_issuers for all to authenticated
using (public.is_admin()) with check (public.is_admin());

create policy "verifier owns requests" on public.verification_requests for select to authenticated
using (verifier_id = (select auth.uid()) or public.is_admin());
create policy "verifier creates requests" on public.verification_requests for insert to authenticated
with check (verifier_id = (select auth.uid()) and public.current_app_role() = 'verifier');

create policy "proof owner or requesting verifier reads" on public.proofs for select to authenticated
using (
  public.is_admin() or
  exists (select 1 from public.credentials c where c.id = credential_id and public.owns_wallet(c.wallet_id)) or
  exists (select 1 from public.verification_requests r where r.id = request_id and r.verifier_id = (select auth.uid()))
);
-- Proof writes and nonce consumption occur only through service-role Edge Functions.

create policy "admin reads otp attempts" on public.otp_attempts for select to authenticated
using (public.is_admin());
create policy "admin reads audit log" on public.audit_log for select to authenticated
using (public.is_admin());
-- Audit is append-only for clients; Edge Functions append via service role only.

revoke all on public.otp_attempts, public.audit_log from anon, authenticated;
revoke all on function public.reserve_otp_attempt(text) from public, anon, authenticated;
revoke all on function public.can_send_otp(text) from public, anon, authenticated;
revoke all on function public.reset_otp_attempts(text) from public, anon, authenticated;
revoke all on function public.consume_proof_nonce(text, text) from public, anon, authenticated;
grant execute on function public.reserve_otp_attempt(text) to service_role;
grant execute on function public.can_send_otp(text) to service_role;
grant execute on function public.reset_otp_attempts(text) to service_role;
grant execute on function public.consume_proof_nonce(text, text) to service_role;
