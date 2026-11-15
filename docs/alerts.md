## Alerts (`scripts/send_alerts.sh`), Person 4

Reads `data/processed_delays.csv` and raises one digest alert for rows with `status = MAJOR_DELAY`.
The delay rule itself (`delay_min >= MAJOR_DELAY_MIN`) is set by Person 2's `config/thresholds.conf`; alerts never recalculate it.

### Run
    scripts/send_alerts.sh                      # dry-run (default): prints the alert, sends nothing
    scripts/send_alerts.sh -m log-only          # appends the full alert list to logs/alerts.log
    scripts/send_alerts.sh -m send -r a@b.com   # emails via mailx and logs
    scripts/send_alerts.sh -i other.csv -n 5    # other input, show only the worst 5 in the message
    bash tests/test_alerts.sh                   # automated tests (use fake mailx, never send)

### Input
Columns used (found by header name): service_date, trip_id, route_id, vehicle_id, stop_id, stop_sequence,
scheduled_arrival_utc, actual_arrival_utc, delay_min, status. Other columns are ignored.
Plain CSV, no quoted fields. Malformed rows are skipped with a warning.

### Behaviour
- One digest message per run, worst delay first, duplicates (same date + trip + stop_sequence) collapsed to the worst.
- Message shows at most MAX_ALERTS_IN_MESSAGE (default 10) alerts; the log keeps all.
- Settings: `config/alerts.conf` (ALERT_MODE, MAIL_TO, MAX_ALERTS_IN_MESSAGE). CLI flags override.
- Stop names are not in the data, so alerts show `stop_id`.

### Exit codes
0 ok (including no alerts) | 1 bad option/config | 2 missing/invalid input | 3 delivery failure (alert still logged)
