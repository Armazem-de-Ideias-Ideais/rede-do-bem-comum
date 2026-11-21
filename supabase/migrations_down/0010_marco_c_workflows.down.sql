-- 0010 DOWN — remove as funções de fluxo do Marco C
do $$
declare r record;
begin
  for r in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'app' and p.proname = any (array['_client_ip_hash', '_antispam', '_hp_tripped', '_check_len', '_norm_locale', '_random_digits', '_random_code', '_sha', '_notify', '_account_email', 'request_takedown', 'mod_decide_takedown', 'report', 'suggest_initiative', 'send_contact_message', '_approve_claim', 'claim_start', 'claim_verify_code', 'claim_resend_code', 'claim_submit_evidence', 'claim_cancel', 'mod_decide_claim', 'manager_update', 'set_accepts_connections', 'set_locale', 'connect_request', 'connect_respond', 'connect_cancel', 'my_connections', 'offer_need_upsert', 'offer_need_remove', 'my_offers_needs', '_invitation_by_token', 'mod_create_invite', 'mod_revoke_invite', 'invite_preview', 'invite_decline', 'invite_accept', 'my_account', 'mod_queue_counts', 'mod_list', 'mod_decide_suggestion', 'mod_mark_contact', 'notification_pending', 'notification_claim', 'notification_done', 'purge_expired']) loop
    execute format('drop function %s', r.sig);
  end loop;
end $$;
