# Data Contract

**Status:** DRAFT by Person 2 (Delay Processing). Person 1 to confirm Section 1; Person 3 (Reports) and Person 4 (Alerts) to confirm Section 3.
**Maintained by:** Person 1 and Person 2 jointly. Change a schema only after the team agrees (see `module_contracts.md`, Working Rules).

## 1. Input from Person 1 (ingestion), read by `scripts/process_delays.sh`

### `data/timetable.csv`
Header (exact names, exact order):
`service_date,trip_id,route_id,stop_id,stop_sequence,scheduled_arrival_utc`

### `data/live_updates.csv`  (standardized output of `ingest.sh`, converted from the JSON feed)
Header (exact names, exact order):
`service_date,trip_id,vehicle_id,stop_id,stop_sequence,actual_arrival_utc,confidence`

| Field | Format and meaning |
|---|---|
| `service_date` | `YYYY-MM-DD`, the **local** service day. Used for matching only. It can differ from the UTC date of the timestamps. |
| `trip_id`, `route_id`, `stop_id`, `vehicle_id` | Non-empty **strings**, no commas. Never treated as numbers (`0968` keeps its leading zero). Same spelling and case in both files. |
| `stop_sequence` | Positive integer. Position of the stop within the trip. |
| `scheduled_arrival_utc`, `actual_arrival_utc` | `YYYY-MM-DDTHH:MM:SSZ`, **UTC**, whole seconds. No other format is accepted (no `25:10:00`, no AM/PM, no time-only values). |
| `confidence` | `high` or `medium`. Records without a reliable actual time are not written to the live file. |

File rules: comma-delimited, UTF-8, header row required, no quoted fields, LF or CRLF. Missing values are not allowed in these files; invalid records are rejected by ingestion.
**To confirm with Person 1:** the live feed is written as `data/live_updates.csv` by `ingest.sh` (the JSON stays as the raw source), and `ingest.sh` and the repo agree on the JSON location (`data/live_updates.json` vs `data/raw/live_updates.json`).

## 2. Matching rules
- Join key: `service_date` + `trip_id` + `stop_sequence`. `stop_id` is then cross-checked; a mismatch is rejected.
- Duplicate live records for one key: higher confidence wins (`high` over `medium`); on a tie the later record in the file wins.
- Duplicate timetable keys: the first record wins.
- Timetable rows with no live update are not errors; they are counted and produce no output row.

## 3. Output: `data/processed_delays.csv` (producer: Person 2; consumers: Person 3 Reports, Person 4 Alerts)
Header (exact names, exact order):
`service_date,trip_id,route_id,vehicle_id,stop_id,stop_sequence,scheduled_arrival_utc,actual_arrival_utc,delay_min,status,confidence`

| Field | Meaning |
|---|---|
| `service_date` .. `stop_sequence` | As in the inputs. `route_id` comes from the timetable, `vehicle_id` from the live update. |
| `scheduled_arrival_utc`, `actual_arrival_utc` | The two matched UTC timestamps, unchanged. |
| `delay_min` | `(actual - scheduled)` in minutes, 2 decimals. **Negative = early.** Computed from full UTC timestamps, so arrivals crossing midnight are handled correctly. |
| `status` | `ON_TIME`, `DELAYED` or `MAJOR_DELAY` (see below). |
| `confidence` | Copied from the live update. |

One row per matched key, in live-file order. Always has the header, even with no rows. Written atomically (a failed run never leaves a partial file).

## 4. Status definitions
Thresholds live in `config/config.sh` (shared): `ON_TIME_MAX_MIN` (default 5) and `MAJOR_DELAY_MIN` (default 15), in minutes.

| Status | Rule |
|---|---|
| `ON_TIME` | `delay_min <= ON_TIME_MAX_MIN` (includes every early arrival) |
| `DELAYED` | `ON_TIME_MAX_MIN < delay_min < MAJOR_DELAY_MIN` |
| `MAJOR_DELAY` | `delay_min >= MAJOR_DELAY_MIN` |

Both boundaries are inclusive as written and compared in whole seconds (exactly 5.00 is ON_TIME; exactly 15.00 is MAJOR_DELAY). `ON_TIME_MAX_MIN` must be less than `MAJOR_DELAY_MIN`.

## 5. Missing or invalid data
- Wrong or missing header, unreadable file, or missing/invalid thresholds: the script stops with an `ERROR:` message on stderr and a non-zero exit code (1 for files/config, 2 for headers). No output file is written.
- A bad individual row (wrong field count, empty field, bad confidence, non-numeric `stop_sequence`, malformed timestamp, no timetable match, `stop_id` mismatch) is skipped and counted. Counts are printed to stderr at the end of the run.
- Exit code 0 means the run finished, even if some rows were skipped.
