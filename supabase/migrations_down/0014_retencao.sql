-- Reverte 0014.
select cron.unschedule(jobid) from cron.job where jobname = 'rbc-retention';
drop function if exists app.purge_retention();
