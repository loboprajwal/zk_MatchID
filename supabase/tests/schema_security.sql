begin;
select plan(5);

select has_table('public', 'identities', 'identity table exists');
select has_table('public', 'wallets', 'wallet table exists');
select has_unique('public', 'identities', 'phone_hash', 'phone hash is database unique');
select has_unique('public', 'credentials', 'doc_fingerprint', 'document fingerprint is database unique');
select has_unique('public', 'proofs', 'nonce', 'proof nonce is database unique');

select * from finish();
rollback;
