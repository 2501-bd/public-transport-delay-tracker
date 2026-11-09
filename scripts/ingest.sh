#!/usr/bin/env bash

# Public Transport Timetable & Delay Tracker
# Person 1: Data Ingestion

set -Eeuo pipefail

# Find the project root (the directory containing this script's parent)
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

TIMETABLE="${TIMETABLE:-$PROJECT_DIR/data/timetable.csv}"
LIVE_JSON="${LIVE_JSON:-$PROJECT_DIR/data/raw/live_updates.json}"
LIVE_CSV="${LIVE_CSV:-$PROJECT_DIR/data/live_updates.csv}"

EXPECTED_HEADER="service_date,trip_id,route_id,stop_id,stop_sequence,scheduled_arrival_utc"
OUTPUT_HEADER="service_date,trip_id,vehicle_id,stop_id,stop_sequence,actual_arrival_utc,confidence"

echo "Starting data ingestion..."

# 1. Check required tools
for tool in jq awk; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "ERROR: Required tool '$tool' is not installed." >&2
        exit 1
    fi
done

# 2. Check that input files exist
if [[ ! -s "$TIMETABLE" ]]; then
    echo "ERROR: Timetable file is missing or empty: $TIMETABLE" >&2
    exit 1
fi

if [[ ! -s "$LIVE_JSON" ]]; then
    echo "ERROR: Live JSON file is missing or empty: $LIVE_JSON" >&2
    exit 1
fi

# 3. Validate the timetable header
actual_header="$(head -n 1 "$TIMETABLE")"
actual_header="${actual_header%$'\r'}"
if [[ "$actual_header" != "$EXPECTED_HEADER" ]]; then
    echo "ERROR: Timetable CSV has an incorrect header." >&2
    echo "Expected: $EXPECTED_HEADER" >&2
    echo "Found:    $actual_header" >&2
    exit 1
fi


# 4. Validate timetable structure and field values
if ! awk -F',' '
    {
        sub(/\r$/, "")
    }

    NR > 1 {
        if (NF != 6) exit 1

        for (i = 1; i <= NF; i++) {
            if ($i == "") exit 1
        }

        # Validate service date format
        if ($1 !~ /^[0-9]{4}-[0-9]{2}-[0-9]{2}$/) exit 1

        # Validate positive integer stop sequence
        if ($5 !~ /^[0-9]+$/ || $5 + 0 <= 0) exit 1

        # Validate UTC timestamp format
        if ($6 !~ /^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$/) exit 1
    }
' "$TIMETABLE"; then
    echo "ERROR: Timetable contains malformed or invalid records." >&2
    exit 1
fi

# 5. Validate JSON syntax and record structure
if ! jq -e '
    type == "array" and
    length > 0 and
    all(.[];
        type == "object" and
        (.service_date | type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$")) and
        (.trip_id | type == "string" and test("^[^,\r\n]+$")) and
        (.vehicle_id | type == "string" and test("^[^,\r\n]+$")) and
        (.stop_id | type == "string" and test("^[^,\r\n]+$")) and
        (.stop_sequence | type == "number" and floor == . and . > 0) and
        (.actual_arrival_utc | type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")) and
        (.confidence | type == "string" and (. == "high" or . == "medium"))
    )
' "$LIVE_JSON" >/dev/null; then
    echo "ERROR: JSON is invalid or contains malformed live-update records." >&2
    exit 1
fi

# 6. Convert JSON records into the standardized CSV format
TEMP_FILE="$(mktemp "$PROJECT_DIR/data/live_updates.XXXXXX")"
trap 'rm -f "$TEMP_FILE"' EXIT

echo "$OUTPUT_HEADER" > "$TEMP_FILE"

jq -r '
    .[] |
    [
        .service_date,
        .trip_id,
        .vehicle_id,
        .stop_id,
        (.stop_sequence | tostring),
        .actual_arrival_utc,
        .confidence
    ] | join(",")
' "$LIVE_JSON" >> "$TEMP_FILE"

# 7. Replace the output only after successful validation and conversion
mv "$TEMP_FILE" "$LIVE_CSV"
trap - EXIT

echo "Data ingestion completed successfully."
echo "Timetable rows: $(( $(wc -l < "$TIMETABLE") - 1 ))"
echo "Live updates:   $(jq 'length' "$LIVE_JSON")"
echo "Output file:    $LIVE_CSV"
