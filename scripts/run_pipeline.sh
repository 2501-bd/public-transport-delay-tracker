#!/usr/bin/env bash
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$ROOT/logs"
LOG_FILE="$LOG_DIR/pipeline_$(date +%Y%m%d_%H%M%S).log"
RETENTION_DAYS=14

mkdir -p "$LOG_DIR"

log() { echo "$(date '+%F %T') [$1] $2" | tee -a "$LOG_FILE"; }

run_step() {
  local num="$1" name="$2" script="$3"
  local path="$ROOT/scripts/$script"

  log INFO "[$num/5] $name: starting"
  if [ ! -f "$path" ]; then
    log ERROR "$script not found"
    exit 1
  fi

  bash "$path" 2>&1 | tee -a "$LOG_FILE"
  local code=${PIPESTATUS[0]}

  if [ "$code" -ne 0 ]; then
    log ERROR "$name failed (exit code $code), pipeline aborted"
    exit "$code"
  fi
  log INFO "$name: finished OK"
}

log INFO "========== Pipeline started =========="
run_step 1 "Data Ingestion"     ingest.sh
run_step 2 "Delay Processing"   process_delays.sh
run_step 3 "Reports & Charts"   generate_report.sh
run_step 4 "Dashboard" generate_dashboard.sh
run_step 5 "Alerts" send_alerts.sh
log INFO "========== Pipeline completed successfully =========="

# Log rotation: delete pipeline logs older than $RETENTION_DAYS days
find "$LOG_DIR" -name 'pipeline_*.log' -mtime +"$RETENTION_DAYS" -delete
