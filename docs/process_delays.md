## Delay Calculation & Processing (`scripts/process_delays.sh`)

Matches scheduled arrivals to live arrivals, computes delay in minutes, classifies each record, and writes `data/processed_delays.csv` for the reporting and alert modules. Bash + awk only.

### Run

```bash
scripts/process_delays.sh                       # uses data/timetable.csv, data/live_updates.csv -> data/processed_delays.csv
scripts/process_delays.sh TT.csv LIVE.csv OUT.csv   # explicit paths
CONFIG=/path/to/config.sh scripts/process_delays.sh
tests/run_tests.sh                              # test suite (hand-written fixtures)
```

Exit codes: `0` ran (bad rows are counted, not fatal), `1` missing file / invalid config, `2` wrong header. Prints `process_delays: starting` first and `process_delays: done -> <output>` last (stdout); the done line is not printed on failure. Works from any directory.
A count summary (rows read, matched, rejected per reason) is printed to **stderr**. It is not a log file.

### Input schema (agreed with ingestion module)

`data/timetable.csv` (header required, exact order):
`service_date,trip_id,route_id,stop_id,stop_sequence,scheduled_arrival_utc`

`data/live_updates.csv` (header required, exact order):
`service_date,trip_id,vehicle_id,stop_id,stop_sequence,actual_arrival_utc,confidence`

- Comma-delimited, UTF-8, no quoted fields or embedded commas. LF or CRLF accepted.
- All IDs are **strings** (e.g. `vehicle_id` `0968` keeps its leading zero).
- `confidence` must be `high` or `medium`. Rows without an actual time must not be in the live file.

### Timestamp rules

- Format: `YYYY-MM-DDTHH:MM:SSZ`, **UTC**, whole seconds. Nothing else is accepted (no `25:10:00`, no AM/PM, no time-only values).
- `service_date` is the **local** service day, not the UTC date. It is used for matching only, never derived from a timestamp. (E.g. `2026-04-17` with a scheduled time of `2026-04-18T00:40:00Z` is correct.)
- Delay is `actual_epoch - scheduled_epoch`. Because both are full UTC timestamps, arrivals crossing midnight need no special handling (`23:58Z` scheduled, `00:04Z` next day actual = +6.00 min).
- Early arrivals produce a **negative** `delay_min` and are classified ON_TIME.
- Precision is whole seconds. If the source has sub-second times, ingestion truncates them, so a delay of 300.5 s becomes 300 s.

### Matching

Join key: `service_date + trip_id + stop_sequence`. `stop_id` is then cross-checked, and a mismatch is rejected.
Duplicate live rows for one key: higher confidence wins (`high` > `medium`); on a tie, the later row in the file wins.
Duplicate timetable keys: first row wins.

### Thresholds (shared `config/config.sh`)

| Setting | Default | Meaning |
|---|---|---|
| `ON_TIME_MAX_MIN` | 5 | `delay_min <= 5` is ON_TIME (inclusive, includes early) |
| `MAJOR_DELAY_MIN` | 15 | `delay_min >= 15` is MAJOR_DELAY (inclusive) |

The script reads these two plain `KEY=value` lines from `config/config.sh` (the shared config; `export` prefixes and trailing `# comments` are fine). Anything in between is DELAYED. Boundaries are compared in whole seconds, so exactly 5.00 is ON_TIME and exactly 15.00 is MAJOR_DELAY. `ON_TIME_MAX_MIN` must be less than `MAJOR_DELAY_MIN`; a missing or invalid value stops the run (exit 1). The values must exist in `config/config.sh`; this module has no thresholds file of its own.

### Output schema: `data/processed_delays.csv`

`service_date,trip_id,route_id,vehicle_id,stop_id,stop_sequence,scheduled_arrival_utc,actual_arrival_utc,delay_min,status,confidence`

`delay_min` has 2 decimals (negative = early). `status` is `ON_TIME`, `DELAYED` or `MAJOR_DELAY`. Rows follow live-file order. The file is replaced atomically, so a failed run never leaves a partial output.
**The reporting and alert modules must agree to this column list before it changes.**

### Rejected rows (counted in the stderr summary)

Wrong field count, empty field, bad confidence, non-numeric `stop_sequence`, malformed timestamp, no timetable match, `stop_id` mismatch. Timetable rows with no live update are counted as `timetable_rows_without_live` and are **not** errors (no data yet, or low-confidence upstream).

### Tests

Run `bash tests/run_tests.sh` (28 checks, prints `PASS`/`FAIL` per check and exits non-zero on any failure). Every expected value was worked out by hand, not copied from the script's output.

| Checklist item | Test label | What it checks |
|---|---|---|
| Early arrivals | `[early]` | 30 s, 5 min and 20 min early give `-0.50`, `-5.00`, `-20.00` and status `ON_TIME` |
| Midnight-crossing timestamps | `[midnight]` | Late across midnight (`23:58Z` to `00:04Z` = `6.00`), early across midnight (`-4.00`), year end (`2026-12-31` to `2027-01-01`), and 29 Feb / 28 Feb to 1 March in 2028 (leap), 2027, 2100 (not leap) and 2000 (leap) |
| Invalid timestamps | `[invalid timestamp]` | `04.56AM`, a space instead of `T`, hour 25, month 13, missing `Z` and a `+05:30` offset are all rejected and counted; only the valid row is written; a bad scheduled time is rejected from the timetable |
| Missing identifiers | `[missing id]` | An empty `trip_id`, `vehicle_id`, `stop_id`, `service_date` or `stop_sequence` is rejected, as is a row with a missing column; a timetable row with an empty `trip_id` is rejected |
| Duplicate records | `[duplicate]` | `high` beats `medium` in either order; on a tie the later row wins; the first timetable row wins; counts of superseded and ignored duplicates are checked |
| Threshold boundary cases | `[boundary]` | With 5 and 15 minutes: `0.00`, `4.98`, `5.00` are ON_TIME; `5.02`, `14.98` are DELAYED; `15.00`, `15.02` are MAJOR_DELAY. With decimal thresholds 2.5 and 7.5: `2.50` ON_TIME, `2.52` and `7.48` DELAYED, `7.50` MAJOR_DELAY |
| Output schema | first two checks | The full output file (header, column order, formats) and the summary counts are compared with `tests/fixtures/expected_output.csv` and `expected_summary.txt` |
| Other | unlabelled checks | Custom thresholds, `config.sh`-style config, invalid or missing config, missing file, wrong header, empty live file, CRLF input, start/done messages, running from another directory |

Fixtures for the first two checks are in `tests/fixtures/`; the labelled cases build their small input files inside `tests/run_tests.sh` so each case sits next to its expected output.

### Known limitations

No quoted-CSV support. Dates are not checked per month (e.g. `2026-02-31` passes). Verified on mawk 1.3.4. The awk code is plain POSIX, but gawk was not tested.
