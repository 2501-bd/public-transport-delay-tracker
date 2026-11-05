#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

INPUT="${1:-$ROOT/data/processed_delays.csv}"
OUTPUT="${2:-$ROOT/reports/summary_report.csv}"

echo "Starting report generation..."

if [[ ! -f "$INPUT" ]]; then
    echo "Error: Input file not found: $INPUT" >&2
    exit 1
fi

mkdir -p "$(dirname "$OUTPUT")"

TEMP_OUTPUT="${OUTPUT}.tmp"
trap 'rm -f "$TEMP_OUTPUT"' EXIT

awk -F',' '
BEGIN {
    OFS = ","
}

NR == 1 {
    for (i = 1; i <= NF; i++) {
        gsub(/\r/, "", $i)
        header[$i] = i
    }

    if (!("route_id" in header) ||
        !("delay_min" in header) ||
        !("status" in header)) {
        print "Error: Required columns are missing." > "/dev/stderr"
        bad_header = 1
        exit 2
    }

    route_col = header["route_id"]
    delay_col = header["delay_min"]
    status_col = header["status"]

    print "report_type,route_id,total_records,average_delay_min,max_delay_min,on_time_records,delayed_records,major_delay_records"
    next
}

{
    route = $route_col
    delay = $delay_col
    status = $status_col

    gsub(/\r/, "", route)
    gsub(/\r/, "", delay)
    gsub(/\r/, "", status)

    if (route == "" ||
        delay !~ /^-?[0-9]+([.][0-9]+)?$/ ||
        (status != "ON_TIME" &&
         status != "DELAYED" &&
         status != "MAJOR_DELAY")) {
        skipped++
        next
    }

    delay += 0
    total++
    sum += delay

    if (total == 1 || delay > max_delay)
        max_delay = delay

    if (status == "ON_TIME")
        on_time++

    if (status == "DELAYED")
        delayed++

    if (status == "MAJOR_DELAY")
        major++

    route_count[route]++
    route_sum[route] += delay

    if (!(route in route_max) || delay > route_max[route])
        route_max[route] = delay

    if (status == "ON_TIME")
        route_on_time[route]++

    if (status == "DELAYED")
        route_delayed[route]++

    if (status == "MAJOR_DELAY")
        route_major[route]++
}

END {
    if (bad_header)
        exit 2

    if (total == 0) {
        print "Error: No valid records found." > "/dev/stderr"
        exit 2
    }

    printf "overall,ALL,%d,%.2f,%.2f,%d,%d,%d\n", \
        total, sum / total, max_delay, on_time, delayed, major

    for (route in route_count) {
        printf "route,%s,%d,%.2f,%.2f,%d,%d,%d\n", \
            route, route_count[route], \
            route_sum[route] / route_count[route], \
            route_max[route], route_on_time[route], \
            route_delayed[route], route_major[route]
    }

    if (skipped > 0)
        printf "Skipped invalid records: %d\n", skipped > "/dev/stderr"
}
' "$INPUT" > "$TEMP_OUTPUT"

mv "$TEMP_OUTPUT" "$OUTPUT"
trap - EXIT

echo "Report saved to: $OUTPUT"
echo "Report generation completed successfully."
