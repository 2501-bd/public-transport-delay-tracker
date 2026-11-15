#!/bin/bash
cd "$(dirname "$0")/.." || exit 1
A=scripts/send_alerts.sh; FIX=tests/fixtures/alerts
export ALERTS_NOW="2026-04-18 10:00:00"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "PASS  $1"; }
bad() { fail=$((fail+1)); echo "FAIL  $1"; }

printf 'LOG_FILE="%s/alerts.log"\n' "$tmp" > "$tmp/base.conf"
printf 'LOG_FILE="%s/alerts.log"\nMAIL_TO="ops@example.com, oncall@example.com"\n' "$tmp" > "$tmp/send.conf"
export ALERT_CONF="$tmp/base.conf"     # isolate tests from the real config/alerts.conf

mkdir -p "$tmp/ok" "$tmp/fail"
printf '#!/bin/bash\necho "ARGS: $*" >> "$MAILX_CAPTURE"\ncat >> "$MAILX_CAPTURE"\n' > "$tmp/ok/mailx"
printf '#!/bin/bash\ncat >/dev/null\nexit 1\n' > "$tmp/fail/mailx"
chmod +x "$tmp/ok/mailx" "$tmp/fail/mailx"
export MAILX_CAPTURE="$tmp/mail.txt"

# 1 zero alerts
out=$($A -i $FIX/zero.csv 2>"$tmp/err"); rc=$?
[[ $rc -eq 0 && -z $out ]] && grep -q 'No MAJOR_DELAY' "$tmp/err" && ok "zero alerts: silent, exit 0" || bad "zero alerts"

# 2 one alert (ON_TIME and DELAYED rows must not alert)
out=$($A -i $FIX/one.csv 2>/dev/null)
[[ $out == *"Trip T-C"* && $out != *"T-A"* && $out != *"T-B"* && $out == *"1 major delay"* ]] \
  && ok "one alert: only T-C" || bad "one alert"

# 3 multiple: order, dedup (worst kept), boundary 15.00, DELAYED excluded, bad row skipped
out=$($A -i $FIX/multiple.csv 2>"$tmp/err")
order=$(echo "$out" | grep -o 'Trip T-.' | tr '\n' ' ')
[[ $order == "Trip T-E Trip T-C Trip T-D " ]] && ok "multiple: 3 alerts, worst first" || bad "multiple order ($order)"
[[ $out == *"29.50"* && $out != *"27.00"* ]] && ok "multiple: duplicate collapsed to worst" || bad "multiple dedup"
[[ $out != *"T-F"* ]] && ok "multiple: DELAYED (14.98) not alerted" || bad "multiple T-F"
grep -q 'skipped=1 duplicates=1' "$tmp/err" && ok "multiple: skip/dup counts" || bad "multiple counts"

# 4 truncation: 12 alerts -> message shows 10, log keeps all 12
{ head -1 $FIX/one.csv
  for i in $(seq 1 12); do echo "2026-04-17,T-$i,5,0968,45691,$i,2026-04-18T01:00:00Z,2026-04-18T01:30:00Z,$((15+i)).00,MAJOR_DELAY,high"; done
} > "$tmp/twelve.csv"
out=$($A -i "$tmp/twelve.csv" -m log-only -n 10 2>/dev/null)
$A -i "$tmp/twelve.csv" -n 10 2>/dev/null > "$tmp/shown.txt"
[[ $(grep -c '^\[[0-9]' "$tmp/shown.txt") -eq 10 ]] && grep -q 'and 2 more' "$tmp/shown.txt" \
  && [[ $(grep -c '^\[[0-9]' "$tmp/alerts.log") -eq 12 ]] && ok "truncation: 10 shown, 12 logged" || bad "truncation"
rm -f "$tmp/alerts.log"

# 5 log-only
out=$($A -i $FIX/multiple.csv -m log-only 2>/dev/null)
[[ -z $out ]] && grep -q 'Trip T-E' "$tmp/alerts.log" && ok "log-only writes log, prints nothing" || bad "log-only"

# 6 dry-run never calls mailx, even with recipients configured
rm -f "$tmp/mail.txt"
ALERT_CONF="$tmp/send.conf" MAILX_CMD="$tmp/ok/mailx" $A -i $FIX/one.csv >/dev/null 2>&1
[[ ! -e $tmp/mail.txt ]] && ok "dry-run: mailx not called" || bad "dry-run called mailx"

# 7 send: exactly one digest, both recipients
rm -f "$tmp/mail.txt"
ALERT_CONF="$tmp/send.conf" MAILX_CMD="$tmp/ok/mailx" $A -i $FIX/multiple.csv -m send >/dev/null 2>&1; rc=$?
[[ $rc -eq 0 && $(grep -c '^ARGS:' "$tmp/mail.txt") -eq 1 ]] && grep -q 'ops@example.com oncall@example.com' "$tmp/mail.txt" \
  && ok "send: one digest, 2 recipients" || bad "send ($rc)"

# 8 send + zero alerts: no email
rm -f "$tmp/mail.txt"
ALERT_CONF="$tmp/send.conf" MAILX_CMD="$tmp/ok/mailx" $A -i $FIX/zero.csv -m send >/dev/null 2>&1
[[ ! -e $tmp/mail.txt ]] && ok "send + zero alerts: no email" || bad "send+zero"

# 9 email failure: exit 3, alert still logged
rm -f "$tmp/alerts.log"
ALERT_CONF="$tmp/send.conf" MAILX_CMD="$tmp/fail/mailx" $A -i $FIX/one.csv -m send >/dev/null 2>&1; rc=$?
[[ $rc -eq 3 ]] && grep -q 'T-C' "$tmp/alerts.log" && ok "mailx failure: exit 3, alert logged" || bad "mailx failure ($rc)"

# 10 send with no recipients: exit 3
$A -i $FIX/one.csv -m send >/dev/null 2>&1; rc=$?
[[ $rc -eq 3 ]] && ok "send without MAIL_TO: exit 3" || bad "no MAIL_TO ($rc)"

# 11 mailx program missing: exit 3
ALERT_CONF="$tmp/send.conf" MAILX_CMD="$tmp/does-not-exist" $A -i $FIX/one.csv -m send >/dev/null 2>&1; rc=$?
[[ $rc -eq 3 ]] && ok "mailx missing: exit 3" || bad "mailx missing ($rc)"

# 12 missing column -> exit 2
printf 'service_date,trip_id\n2026-04-17,T-1\n' > "$tmp/badhdr.csv"
$A -i "$tmp/badhdr.csv" >/dev/null 2>&1; rc=$?
[[ $rc -eq 2 ]] && ok "missing columns: exit 2" || bad "bad header ($rc)"

# 13 missing input file -> exit 2
$A -i "$tmp/nope.csv" >/dev/null 2>&1; rc=$?
[[ $rc -eq 2 ]] && ok "missing input: exit 2" || bad "missing input ($rc)"

# 14 bad mode / bad option -> exit 1
$A -i $FIX/one.csv -m banana >/dev/null 2>&1; rc=$?
[[ $rc -eq 1 ]] && ok "invalid mode: exit 1" || bad "bad mode ($rc)"

echo "----"; echo "passed=$pass failed=$fail"; exit $(( fail > 0 ))
