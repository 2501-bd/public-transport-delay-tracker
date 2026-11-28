# Logging & Automation

## Log retention policy
- Each pipeline run writes `logs/pipeline_<timestamp>.log`.
- Logs older than 14 days are deleted automatically at the end of each run
  (`RETENTION_DAYS=14` in `scripts/run_pipeline.sh`).
- To change the period, edit that one variable.

## Cron scheduling
The pipeline runs automatically every day at 07:00 via cron:

    0 7 * * * /home/<user>/public-transport-delay-tracker/scripts/run_pipeline.sh >> /home/<user>/public-transport-delay-tracker/logs/cron.log 2>&1

- Fields are: minute, hour, day of month, month, day of week.
- Cron needs absolute paths, so replace `<user>` with your username.
- Output of each scheduled run goes to `logs/cron.log`.
- To install: run `crontab -e`, paste the line, save.
- To check: run `crontab -l`.
- Cron must be running (`service cron status`). On WSL it only runs while WSL is open.
