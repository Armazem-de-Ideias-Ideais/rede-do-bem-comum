-- 0011 DOWN — remove a superfície exposta do Marco C (mantém a do Marco B)
drop view if exists api.attribution_sources, api.offers_needs_feed, api.country_counts, api.public_stats, api.entity_list;
do $$
declare r record;
begin
  for r in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'api' and p.proname = any (array['entity_page','sister_initiatives','request_takedown','report',
              'suggest_initiative','send_contact_message','invite_preview','invite_decline','my_account','set_locale',
              'claim_start','claim_verify_code','claim_resend_code','claim_submit_evidence','claim_cancel','manager_update',
              'set_accepts_connections','connect_request','connect_respond','connect_cancel','my_connections',
              'offer_need_upsert','offer_need_remove','my_offers_needs','invite_accept','mod_queue_counts','mod_list',
              'mod_decide_takedown','mod_decide_claim','mod_decide_suggestion','mod_mark_contact','mod_create_invite',
              'mod_revoke_invite','notification_pending','notification_claim','notification_done','purge_expired']) loop
    execute format('drop function %s', r.sig);
  end loop;
end $$;
