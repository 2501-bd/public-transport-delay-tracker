# Project File Guide

**Status:** Initial structure — pending team confirmation

This document explains the purpose of each project file, its owner, and what should be stored in it.

## 1. Project Root

### `README.md`
**Owner:** Coordinator (Person 3), with team contributions

Contains:
- Project overview and objectives
- Features and tools used
- Setup and execution instructions
- Sample output or screenshots
- Team contributions and limitations

### `.gitignore`
**Owner:** Coordinator (Person 3)

Contains patterns for files Git should ignore, such as temporary files, local environment files, and generated logs where appropriate.

### `config/config.sh`
**Owner:** Shared; changes coordinated by the team

Contains:
- Agreed delay thresholds and status settings
- Shared file paths and other configurable values
- Settings used by multiple scripts

Do not duplicate settings already defined elsewhere. Agree on shared variable names before using them across modules.

## 2. Data Files — `data/`

### `data/timetable.csv`
**Owner:** Person 1 — Data Ingestion

Contains scheduled arrival records in the agreed CSV format.

### `data/live_updates.json`
**Owner:** Person 1 — Data Ingestion

Contains actual arrival updates in the agreed JSON format.

### `data/processed_delays.csv`
**Producer:** Person 2 — Delay Processing  
**Consumers:** Person 3 — Reports; Person 4 — Alerts

Contains matched scheduled and actual arrival records, calculated delays, and status classifications in the agreed format.

## 3. Scripts — `scripts/`

### `scripts/ingest.sh`
**Owner:** Person 1

Contains the Bash implementation for obtaining or loading timetable and live-update data, validating input where appropriate, and writing the agreed output files.

### `scripts/process_delays.sh`
**Owner:** Person 2

Contains the implementation for matching records, calculating delays, classifying statuses, and producing the processed CSV.

### `scripts/generate_report.sh`
**Owner:** Person 3 — Reports & Charts

Contains the implementation for reading processed data and generating report outputs. Use Bash and appropriate tools such as awk and gnuplot.

### `scripts/send_alerts.sh`
**Owner:** Person 4 — Alerts

Contains the implementation for identifying qualifying delays and producing or sending alerts using the team's agreed approach.

### `scripts/run_pipeline.sh`
**Owner:** Person 5 — Logging & Automation

Contains the orchestration logic for running modules in the agreed order, checking failures, and coordinating execution logs.

It should call the other scripts rather than duplicate their implementations.

## 4. Reports — `reports/`

### `reports/daily_summary.csv`
**Producer:** Person 3

Contains aggregate statistics derived from processed data, using agreed column names and calculation rules.

### `reports/report.html`
**Producer:** Person 3

Contains the human-readable report, summary statistics, and embedded or linked charts.

### `reports/charts/`
**Producer:** Person 3

Stores generated chart images and, if agreed, related gnuplot scripts.

## 5. Logs — `logs/`

**Owner:** Person 5

Stores execution logs, including timestamps, module execution results, and useful error information. Agree on log naming and retention.

## 6. Configuration — `config/`

### `config/config.sh`
Contains shared settings only. Keep secrets out of version control.

## 7. Tests — `tests/`

**Ownership:** Each module owner tests their own functionality; Person 5 coordinates end-to-end testing.

Stores test inputs, test scripts, and expected outputs. Add tests for normal cases, missing data, malformed input, and failure handling as relevant.

## 8. Documentation — `docs/`

### `docs/data_contract.md`
**Maintained by:** Person 1 and Person 2 jointly

Documents the agreed input/output schemas, field meanings, formats, matching rules, status definitions, and handling of missing or invalid data. Person 3 and Person 4 review whether the processed output meets their needs.

### `docs/module_contracts.md`
Contains this file guide: the purpose, ownership, and expected contents of project files.

## 9. Working Rules

- Each person edits their assigned scripts and owned outputs.
- Shared schemas and settings must be agreed before they are changed.
- Generated reports and charts are outputs, not manually maintained source files.
- New files can be added when needed; this structure is a starting point, not a restriction.
- Record significant interface changes and update the relevant documentation.
