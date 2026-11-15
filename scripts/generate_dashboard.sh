#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

REPORT="$ROOT/reports/summary_report.csv"
CHART_DATA="$ROOT/reports/charts/average_delay_sorted.dat"

echo "Preparing dashboard assets..."

if [[ ! -f "$REPORT" ]]; then
    echo "ERROR: Summary report not found."
    exit 1
fi

mkdir -p "$ROOT/reports/charts"

# Prepare route-wise average delay data, sorted from highest to lowest.
awk -F',' 'NR > 2 {print $2, $4}' "$REPORT" |
    sort -k2,2nr > "$CHART_DATA"

echo "Chart data prepared."

# Generate the route-wise chart.
cd "$ROOT"
gnuplot scripts/average_delay.gnuplot

echo "GNUplot chart generated."

# Generate the HTML report.
bash scripts/generate_html_report.sh

echo "Dashboard assets generated successfully."
