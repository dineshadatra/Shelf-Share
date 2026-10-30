begin;

-- Every externally executed collection/refund/transfer/hold call may be retried
-- by the outbox after timeouts. Provider idempotency is therefore a mandatory
-- capability, not merely an optional adapter convention.
alter table public.payment_provider_approvals
  add column if not exists supports_idempotency boolean not null default false;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname='payment_provider_idempotency_required'
      and conrelid='public.payment_provider_approvals'::regclass
  ) then
    alter table public.payment_provider_approvals
      add constraint payment_provider_idempotency_required
      check (not enabled_for_rent or supports_idempotency);
  end if;
end;
$$;

-- Existing enabled approvals cannot be silently grandfathered into retryable
-- money movement: deployment requires explicit re-attestation by Finance.
update public.payment_provider_approvals
  set enabled_for_rent=false,enabled_for_deposits=false
  where not supports_idempotency;

commit;
