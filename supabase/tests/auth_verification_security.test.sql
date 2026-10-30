begin;

select plan(10);

select ok(
  (select relrowsecurity from pg_class where oid = 'public.identity_documents'::regclass),
  'identity_documents has row-level security enabled'
);
select ok(
  (select relrowsecurity from pg_class where oid = 'public.user_verifications'::regclass),
  'user_verifications has row-level security enabled'
);
select ok(
  (select relrowsecurity from pg_class where oid = 'public.verification_cases'::regclass),
  'verification_cases has row-level security enabled'
);
select ok(
  not has_table_privilege('authenticated', 'public.identity_documents', 'SELECT'),
  'authenticated clients cannot read identity document metadata directly'
);
select ok(
  not has_table_privilege('authenticated', 'public.identity_documents', 'INSERT'),
  'authenticated clients cannot write identity document records directly'
);
select ok(
  not has_table_privilege('authenticated', 'public.user_verifications', 'UPDATE'),
  'authenticated clients cannot change verification status directly'
);
select ok(
  not has_table_privilege('authenticated', 'public.verification_case_files', 'SELECT'),
  'authenticated clients cannot read verification file keys'
);
select ok(
  not has_table_privilege('authenticated', 'public.verification_cases', 'SELECT'),
  'authenticated clients cannot read private review cases'
);
select ok(
  not has_table_privilege('authenticated', 'public.verification_document_access_audit', 'SELECT'),
  'authenticated clients cannot inspect document access logs'
);
select ok(
  (select prosecdef from pg_proc where oid = 'public.review_verification_case(uuid,text,text,text,uuid,boolean)'::regprocedure),
  'verification decision RPC runs as security definer and applies explicit role checks'
);

select * from finish();
rollback;
