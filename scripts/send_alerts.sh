#!/bin/bash
# Alerts module: reads data/processed_delays.csv, alerts on status MAJOR_DELAY.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INPUT_FILE="$ROOT/data/processed_delays.csv"
THRESHOLDS_FILE="${THRESHOLDS_FILE:-$ROOT/config/thresholds.conf}"   # shared with Person 2
ALERT_CONF="${ALERT_CONF:-$ROOT/config/alerts.conf}"
LOG_FILE="${LOG_FILE:-$ROOT/logs/alerts.log}"
MAILX_CMD="${MAILX_CMD:-mailx}"
MAJOR_DELAY_MIN=15
ALERT_MODE="dry-run"
MAIL_TO=""
MAX_ALERTS_IN_MESSAGE=10
MAIL_SUBJECT_PREFIX="[Transit Alert]"

info() { printf '%s INFO  %s\n' "$(date '+%F %T')" "$*" >&2; }
warn() { printf '%s WARN  %s\n' "$(date '+%F %T')" "$*" >&2; }
err()  { printf '%s ERROR %s\n' "$(date '+%F %T')" "$*" >&2; }

usage() {
  cat <<'USAGE'
Usage: send_alerts.sh [-i input.csv] [-m mode] [-r recipients] [-n max] [-h]
  -i  input CSV (default: data/processed_delays.csv)
  -m  dry-run (print only, default) | log-only (write log) | send (mailx + log)
  -r  recipients for send mode (space or comma separated)
  -n  max alerts shown in the message (0 = all); the log always has all
Alerts on rows whose status is MAJOR_DELAY (rule set in config/thresholds.conf).
Exit codes: 0 ok (incl. no alerts), 1 usage/config, 2 input problem, 3 delivery failure
USAGE
}

parse_args() {
  CLI_INPUT="" CLI_MODE="" CLI_TO="" CLI_MAX=""
  local opt; OPTIND=1
  while getopts ":i:m:r:n:h" opt; do
    case $opt in
      i) CLI_INPUT=$OPTARG ;;
      m) CLI_MODE=$OPTARG ;;
      r) CLI_TO=$OPTARG ;;
      n) CLI_MAX=$OPTARG ;;
      h) usage; return 100 ;;
      :) err "option -$OPTARG needs an argument"; return 1 ;;
      *) err "unknown option -$OPTARG"; usage >&2; return 1 ;;
    esac
  done
}

load_config() {
  # shellcheck disable=SC1090
  [[ -f $THRESHOLDS_FILE ]] && { source "$THRESHOLDS_FILE" || { err "bad $THRESHOLDS_FILE"; return 1; }; }
  # shellcheck disable=SC1090
  [[ -f $ALERT_CONF ]] && { source "$ALERT_CONF" || { err "bad $ALERT_CONF"; return 1; }; }
  [[ -n $CLI_INPUT ]] && INPUT_FILE=$CLI_INPUT
  [[ -n $CLI_MODE  ]] && ALERT_MODE=$CLI_MODE
  [[ -n $CLI_TO    ]] && MAIL_TO=$CLI_TO
  [[ -n $CLI_MAX   ]] && MAX_ALERTS_IN_MESSAGE=$CLI_MAX
  case $ALERT_MODE in dry-run|log-only|send) ;; *)
    err "invalid mode '$ALERT_MODE' (dry-run|log-only|send)"; return 1 ;; esac
  [[ $MAJOR_DELAY_MIN =~ ^[0-9]+(\.[0-9]+)?$ ]] || { err "bad MAJOR_DELAY_MIN '$MAJOR_DELAY_MIN'"; return 1; }
  [[ $MAX_ALERTS_IN_MESSAGE =~ ^[0-9]+$ ]] || { err "bad MAX_ALERTS_IN_MESSAGE '$MAX_ALERTS_IN_MESSAGE'"; return 1; }
}

validate_input() {
  [[ -r $INPUT_FILE ]] || { err "input not readable: $INPUT_FILE"; return 2; }
  [[ -s $INPUT_FILE ]] || { err "input is empty: $INPUT_FILE"; return 2; }
}

# TSV out: date route trip vehicle stop seq scheduled actual delay
detect_major_delays() {
  awk -F',' '
    function trim(s) { gsub(/^[ \t\r]+|[ \t\r]+$/, "", s); return s }
    BEGIN {
      OFS = "\t"
      n = split("service_date trip_id route_id vehicle_id stop_id stop_sequence scheduled_arrival_utc actual_arrival_utc delay_min status", req, " ")
    }
    NR == 1 {
      nf = NF
      for (i = 1; i <= NF; i++) col[trim($i)] = i
      for (k = 1; k <= n; k++)
        if (!(req[k] in col)) { printf "ERROR missing required column: %s\n", req[k] > "/dev/stderr"; bad = 1 }
      next
    }
    bad { next }
    {
      if ($0 ~ /^[ \t\r]*$/) next
      if (NF != nf) { printf "WARN line %d skipped: expected %d fields, got %d\n", NR, nf, NF > "/dev/stderr"; skipped++; next }
      st = toupper(trim($col["status"]))
      if (st != "ON_TIME" && st != "DELAYED" && st != "MAJOR_DELAY") {
        printf "WARN line %d skipped: unknown status \"%s\"\n", NR, st > "/dev/stderr"; skipped++; next
      }
      if (st != "MAJOR_DELAY") next
      d = trim($col["delay_min"])
      if (d !~ /^-?[0-9]+(\.[0-9]+)?$/) {
        printf "WARN line %d skipped: bad delay_min \"%s\"\n", NR, d > "/dev/stderr"; skipped++; next
      }
      dn = d + 0
      key = trim($col["service_date"]) SUBSEP trim($col["trip_id"]) SUBSEP trim($col["stop_sequence"])
      line = trim($col["service_date"]) OFS trim($col["route_id"]) OFS trim($col["trip_id"]) OFS \
             trim($col["vehicle_id"]) OFS trim($col["stop_id"]) OFS trim($col["stop_sequence"]) OFS \
             trim($col["scheduled_arrival_utc"]) OFS trim($col["actual_arrival_utc"]) OFS d
      if (key in rec) { dups++; if (dn > dly[key]) { rec[key] = line; dly[key] = dn }; next }
      order[++cnt] = key; rec[key] = line; dly[key] = dn
    }
    END {
      if (bad) exit 2
      for (i = 1; i <= cnt; i++) print rec[order[i]]
      printf "INFO skipped=%d duplicates=%d\n", skipped + 0, dups + 0 > "/dev/stderr"
    }
  ' "$INPUT_FILE"
}

build_message() {   # $1=threshold $2=source $3=max to show (0=all) ; sorted TSV on stdin
  awk -F'\t' -v thr="$1" -v src="$2" -v max="$3" -v now="${ALERTS_NOW:-$(date '+%F %T')}" '
    { r[NR] = $0 }
    END {
      shown = (max > 0 && NR > max) ? max : NR
      printf "MAJOR DELAY ALERT: %d service stop(s) classified MAJOR_DELAY (>= %s min)\n", NR, thr
      printf "Generated: %s\nSource: %s\n", now, src
      if (shown < NR) printf "Showing the worst %d of %d.\n", shown, NR
      for (i = 1; i <= shown; i++) {
        split(r[i], f, "\t")
        printf "\n[%d] Route %s / Trip %s (vehicle %s) - %s min late\n", i, f[2], f[3], f[4], f[9]
        printf "    Service date: %s\n    Stop:         %s (sequence %s)\n", f[1], f[5], f[6]
        printf "    Scheduled:    %s\n    Actual:       %s\n    Delay:        %s min\n", f[7], f[8], f[9]
      }
      if (shown < NR) printf "\n... and %d more not shown (full list: logs/alerts.log in log-only/send mode)\n", NR - shown
    }'
}

write_log() {   # $1=subject $2=full body
  mkdir -p "$(dirname "$LOG_FILE")" || return 1
  printf '=== %s ===\nSubject: %s\n%s\n\n' "$(date '+%F %T')" "$1" "$2" >> "$LOG_FILE"
}

deliver() {   # $1=subject $2=message body $3=full body (for the log)
  local subject=$1 body=$2 full=$3
  case $ALERT_MODE in
    dry-run)
      printf 'Subject: %s\nTo: %s\n\n%s\n' "$subject" "${MAIL_TO:-<not configured>}" "$body" ;;
    log-only)
      write_log "$subject" "$full" || { err "cannot write $LOG_FILE"; return 3; }
      info "alerts appended to $LOG_FILE" ;;
    send)
      write_log "$subject" "$full" || warn "cannot write $LOG_FILE"
      [[ -n $MAIL_TO ]] || { err "MAIL_TO not set; alerts logged but NOT emailed"; return 3; }
      command -v "$MAILX_CMD" >/dev/null 2>&1 || { err "$MAILX_CMD not found; alerts logged but NOT emailed"; return 3; }
      local -a rcpts; IFS=', ' read -r -a rcpts <<< "$MAIL_TO"
      if printf '%s\n' "$body" | "$MAILX_CMD" -s "$subject" "${rcpts[@]}"; then
        info "digest sent to: ${rcpts[*]}"
      else
        err "mailx failed; alerts are in $LOG_FILE"; return 3
      fi ;;
  esac
}

main() {
  local rc=0
  parse_args "$@"; rc=$?
  (( rc == 100 )) && return 0
  (( rc != 0 )) && return 1
  load_config    || return 1
  validate_input || return 2

  local tsv
  tsv=$(detect_major_delays) || rc=$?
  if (( rc != 0 )); then err "could not process $INPUT_FILE"; return 2; fi
  if [[ -z $tsv ]]; then
    info "No MAJOR_DELAY rows in $INPUT_FILE; nothing sent"
    return 0
  fi

  tsv=$(printf '%s\n' "$tsv" | sort -t$'\t' -k9,9nr -k1,1 -k3,3 -k6,6n)   # worst first
  local count subject body full
  count=$(printf '%s\n' "$tsv" | wc -l | tr -d ' ')
  subject="$MAIL_SUBJECT_PREFIX $count major delay(s) (>= $MAJOR_DELAY_MIN min)"
  body=$(printf '%s\n' "$tsv" | build_message "$MAJOR_DELAY_MIN" "$INPUT_FILE" "$MAX_ALERTS_IN_MESSAGE")
  full=$(printf '%s\n' "$tsv" | build_message "$MAJOR_DELAY_MIN" "$INPUT_FILE" 0)
  deliver "$subject" "$body" "$full"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  set -u -o pipefail
  main "$@"
  exit $?
fi
