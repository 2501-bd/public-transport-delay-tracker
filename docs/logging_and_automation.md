# Logging & Automation

## Log retention policy
- Each pipeline run writes `logs/pipeline_<timestamp>.log`.
- Logs older than 14 days are deleted automatically at the end of each run
  (`RETENTION_DAYS=14` in `scripts/run_pipeline.sh`).
- To change the period, edit that one variable.
