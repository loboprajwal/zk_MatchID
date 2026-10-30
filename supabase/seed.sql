-- LOCAL DEMO ONLY. These accounts use fictional identities and must never be
-- copied into a hosted or production Supabase project.
insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, email_change, email_change_token_new, recovery_token
) values
  ('00000000-0000-4000-8000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'admin@matchid.demo', extensions.crypt('DemoAdmin!123', extensions.gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{"display_name":"Demo Admin"}', now(), now(), '', '', '', ''),
  ('00000000-0000-4000-8000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'verifier@matchid.demo', extensions.crypt('DemoVerifier!123', extensions.gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{"display_name":"Cinema Gate 1"}', now(), now(), '', '', '', ''),
  ('00000000-0000-4000-8000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'holder1@matchid.demo', extensions.crypt('DemoHolder!123', extensions.gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{"display_name":"Demo Holder One"}', now(), now(), '', '', '', ''),
  ('00000000-0000-4000-8000-000000000004', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'holder2@matchid.demo', extensions.crypt('DemoHolder!123', extensions.gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{"display_name":"Demo Holder Two"}', now(), now(), '', '', '', '')
on conflict (id) do nothing;

update public.profiles set role = 'admin' where id = '00000000-0000-4000-8000-000000000001';
update public.profiles set role = 'verifier' where id = '00000000-0000-4000-8000-000000000002';

