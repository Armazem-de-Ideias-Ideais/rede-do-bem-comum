-- Reverte 0013: remove agendamentos, gatilho e funções. O segredo do Vault é mantido (apague à mão se quiser).
select cron.unschedule(jobid) from cron.job where jobname in ('rbc-notify-drain', 'rbc-purge');
drop trigger if exists notify_outbox_webhook on app.notification_outbox;
drop function if exists app._notify_outbox_trigger();
drop function if exists app._notify_call(jsonb);
