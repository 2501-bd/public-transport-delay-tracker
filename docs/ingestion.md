# Data Ingestion Module — Person 1

## 1. Overview

The Data Ingestion module is responsible for preparing timetable and live transport update data for downstream processing.

The module reads a timetable CSV file and a live-update JSON feed, validates their structure and fields, and generates a standardized live-update CSV file.

## 2. Files and Responsibilities

| File | Purpose |
|---|---|
| `scripts/ingest.sh` | Main ingestion script |
| `data/timetable.csv` | Scheduled transport information |
| `data/raw/live_updates.json` | Raw live-update JSON feed |
| `data/live_updates.csv` | Standardized live-update output |

## 3. Technologies Used

- Bash — ingestion workflow and error handling.
- jq — JSON parsing and validation.
- awk — CSV structure and field validation.

## 4. Input Formats

### Timetable CSV

Expected header:

`service_date,trip_id,route_id,stop_id,stop_sequence,scheduled_arrival_utc`

### Live Updates JSON

Each JSON record contains:

- `service_date`
- `trip_id`
- `vehicle_id`
- `stop_id`
- `stop_sequence`
- `actual_arrival_utc`
- `confidence`

Confidence must be either `high` or `medium`.

Timestamps use the UTC format `YYYY-MM-DDTHH:MM:SSZ`.

## 5. Processing Workflow

1. Check that required tools are installed.
2. Verify that the timetable and JSON input files exist and are non-empty.
3. Validate the timetable header.
4. Validate timetable field counts, required values, date format, stop sequence, and timestamp format.
5. Validate JSON syntax, record structure, field types, and allowed confidence values.
6. Reject empty JSON feeds.
7. Convert valid JSON records into the standardized CSV format.
8. Write to a temporary file and replace the output only after successful validation.

## 6. Output Format

The generated CSV uses this header:

`service_date,trip_id,vehicle_id,stop_id,stop_sequence,actual_arrival_utc,confidence`

The output is compatible with the input contract expected by the processing module.

## 7. Error Handling

The script handles:

- Missing or empty input files.
- Incorrect timetable headers.
- Malformed CSV rows.
- Empty CSV fields.
- Invalid date, timestamp, and stop-sequence formats.
- Invalid JSON syntax.
- Missing or incorrectly typed JSON fields.
- Invalid confidence values.
- Empty JSON arrays.

The script exits with an error when validation fails. A temporary output file is used so that an existing valid output is not replaced by a failed ingestion attempt.

## 8. Running the Module

From the project root:

```bash
chmod +x scripts/ingest.sh
./scripts/ingest.sh
```

Optional input-path overrides:

```bash
TIMETABLE=/path/to/timetable.csv \
LIVE_JSON=/path/to/live_updates.json \
LIVE_CSV=/path/to/output.csv \
./scripts/ingest.sh
```

## 9. Data Source and Limitations

The current live-update JSON feed is simulated by converting records from the available processed dataset into the required JSON structure.

It is not a direct connection to a real-time public transport API. The simulated feed allows the ingestion and validation workflow to be demonstrated and tested.

A live API connection can be added when a suitable transport data provider is available.

## 10. Testing

The ingestion module was tested with:

- Valid input containing 8,066 records.
- Invalid JSON syntax.
- Invalid JSON field values.
- Empty JSON arrays.
- Missing timetable and JSON files.
- Incorrect timetable headers.
- Malformed timetable rows.
- Empty timetable fields.
- Invalid stop sequences.
- CRLF-formatted timetable files.

The successful ingestion generated 8,066 live-update records.