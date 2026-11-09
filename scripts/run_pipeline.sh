#!/usr/bin/env bash
set -euo pipefail

# Get project root directory
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOG_DIR="$ROOT/logs"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_FILE="$LOG_DIR/pipeline_$TIMESTAMP.log"

# Ensure log directory exists
mkdir -p "$LOG_DIR"

# Redirect all output to both console and the timestamped log file
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=========================================="
echo "Starting Public Transport Pipeline: $(date)"
echo "=========================================="

# Step 1: Data Ingestion (Person 1)
echo "[1/4] Running Data Ingestion..."
if [ -f "$ROOT/scripts/ingest.sh" ]; then
    bash "$ROOT/scripts/ingest.sh"
else
    echo "ERROR: ingest.sh not found!"
    exit 1
fi

# Step 2: Delay Processing (Person 2)
echo "[2/4] Running Delay Processing..."
if [ -f "$ROOT/scripts/process_delays.sh" ]; then
    bash "$ROOT/scripts/process_delays.sh"
else
    echo "ERROR: process_delays.sh not found!"
    exit 1
fi

# Step 3: Report Generation (Person 3)
echo "[3/4] Generating Reports & Charts..."
if [ -f "$ROOT/scripts/generate_report.sh" ]; then
    bash "$ROOT/scripts/generate_report.sh"
else
    echo "ERROR: generate_report.sh not found!"
    exit 1
fi

# Step 4: Alerts (Person 4)
echo "[4/4] Checking and Sending Alerts..."
if [ -f "$ROOT/scripts/send_alerts.sh" ]; then
    bash "$ROOT/scripts/send_alerts.sh"
else
    echo "ERROR: send_alerts.sh not found!"
    exit 1
fi

echo "=========================================="
echo "Pipeline completed successfully at: $(date)"
echo "=========================================="
