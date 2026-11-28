#!/usr/bin/env bash
# Runs process_delays.sh against hand-written fixtures and fails on any difference.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
SCRIPT="$ROOT/scripts/process_delays.sh"
FX="$HERE/fixtures"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export CONFIG="$FX/thresholds.conf"   # tests never depend on the team config
pass=0; fail=0
ok()  { echo "PASS: $1"; pass=$((pass+1)); }
bad() { echo "FAIL: $1"; fail=$((fail+1)); }

# 1. Main fixture: output file and summary counts
"$SCRIPT" "$FX/timetable.csv" "$FX/live_updates.csv" "$TMP/out.csv" >/dev/null 2> "$TMP/summary.txt"
diff -u "$FX/expected_output.csv" "$TMP/out.csv"      && ok "output matches expected"  || bad "output differs"
diff -u "$FX/expected_summary.txt" "$TMP/summary.txt" && ok "summary matches expected" || bad "summary differs"

# 2. Custom thresholds change classification (3/6 instead of 5/15)
printf 'ON_TIME_MAX_MIN=3\nMAJOR_DELAY_MIN=6\n' > "$TMP/t.conf"
CONFIG="$TMP/t.conf" "$SCRIPT" "$FX/timetable.csv" "$FX/live_updates.csv" "$TMP/out2.csv" >/dev/null 2>&1
grep -q ',6.00,MAJOR_DELAY,' "$TMP/out2.csv" && grep -q ',5.00,DELAYED,' "$TMP/out2.csv" \
  && ok "custom thresholds respected" || bad "custom thresholds ignored"

# 3. Bad config: thresholds in wrong order -> exit 1
printf 'ON_TIME_MAX_MIN=10\nMAJOR_DELAY_MIN=5\n' > "$TMP/bad.conf"
CONFIG="$TMP/bad.conf" "$SCRIPT" "$FX/timetable.csv" "$FX/live_updates.csv" "$TMP/o3.csv" >/dev/null 2>&1
[[ $? -eq 1 ]] && ok "bad config rejected (exit 1)" || bad "bad config not rejected"

# 4. Non-numeric threshold -> exit 1
printf 'ON_TIME_MAX_MIN=abc\nMAJOR_DELAY_MIN=15\n' > "$TMP/bad2.conf"
CONFIG="$TMP/bad2.conf" "$SCRIPT" "$FX/timetable.csv" "$FX/live_updates.csv" "$TMP/o4.csv" >/dev/null 2>&1
[[ $? -eq 1 ]] && ok "non-numeric threshold rejected" || bad "non-numeric threshold accepted"

# 5. Missing input file -> exit 1, no output file left behind
"$SCRIPT" "$TMP/nope.csv" "$FX/live_updates.csv" "$TMP/o5.csv" >/dev/null 2>&1
[[ $? -eq 1 && ! -e "$TMP/o5.csv" ]] && ok "missing file -> exit 1, no output" || bad "missing file handling"

# 6. Wrong header -> exit 2
printf 'a,b,c\n1,2,3\n' > "$TMP/wronghdr.csv"
"$SCRIPT" "$TMP/wronghdr.csv" "$FX/live_updates.csv" "$TMP/o6.csv" >/dev/null 2>&1
[[ $? -eq 2 ]] && ok "wrong header -> exit 2" || bad "wrong header not caught"

# 7. Header-only live file -> header-only output, exit 0
head -n1 "$FX/live_updates.csv" > "$TMP/emptylive.csv"
"$SCRIPT" "$FX/timetable.csv" "$TMP/emptylive.csv" "$TMP/o7.csv" >/dev/null 2>&1
[[ $? -eq 0 && $(wc -l < "$TMP/o7.csv") -eq 1 ]] && ok "empty live file -> header only" || bad "empty live file handling"

# 8. CRLF line endings are tolerated
sed 's/$/\r/' "$FX/timetable.csv" > "$TMP/tt_crlf.csv"; sed 's/$/\r/' "$FX/live_updates.csv" > "$TMP/lv_crlf.csv"
"$SCRIPT" "$TMP/tt_crlf.csv" "$TMP/lv_crlf.csv" "$TMP/o8.csv" >/dev/null 2>&1
diff -q "$FX/expected_output.csv" "$TMP/o8.csv" >/dev/null && ok "CRLF input handled" || bad "CRLF input mishandled"

# 9. Prints "starting" and "done" on success; no "done" on failure
OUT9="$("$SCRIPT" "$FX/timetable.csv" "$FX/live_updates.csv" "$TMP/o9.csv" 2>/dev/null)"
[[ "$OUT9" == *"process_delays: starting"* && "$OUT9" == *"process_delays: done"* ]] \
  && ok "prints starting and done lines" || bad "missing starting/done lines"
FAIL9="$("$SCRIPT" "$TMP/nope.csv" "$FX/live_updates.csv" "$TMP/o10.csv" 2>/dev/null)"
[[ "$FAIL9" == *"starting"* && "$FAIL9" != *"done"* ]] && ok "no done line on failure" || bad "done printed despite failure"

# 10. Runs from any working directory (no hardcoded paths)
( cd / && "$SCRIPT" "$FX/timetable.csv" "$FX/live_updates.csv" "$TMP/o11.csv" >/dev/null 2>&1 )
diff -q "$FX/expected_output.csv" "$TMP/o11.csv" >/dev/null && ok "works from another directory" || bad "depends on working directory"

# 11. Reads thresholds from a shared config.sh-style file (export, comments, other variables)
cat > "$TMP/shared_config.sh" <<'CFG'
#!/usr/bin/env bash
LOG_DIR=logs
export ON_TIME_MAX_MIN=3   # minutes
export MAJOR_DELAY_MIN="6"
CFG
CONFIG="$TMP/shared_config.sh" "$SCRIPT" "$FX/timetable.csv" "$FX/live_updates.csv" "$TMP/o12.csv" >/dev/null 2>&1
grep -q ',6.00,MAJOR_DELAY,' "$TMP/o12.csv" && ok "reads thresholds from config.sh-style file" || bad "config.sh-style file not parsed"

# 12. Config without the thresholds fails clearly (exit 1)
printf 'LOG_DIR=logs\n' > "$TMP/empty_config.sh"
CONFIG="$TMP/empty_config.sh" "$SCRIPT" "$FX/timetable.csv" "$FX/live_updates.csv" "$TMP/o13.csv" >/dev/null 2>&1
[[ $? -eq 1 ]] && ok "config missing thresholds -> exit 1" || bad "missing thresholds not caught"


# ======================================================================
# CHECKLIST TESTS (each section is named after an item on the project checklist)
# Helpers: build a small timetable/live pair, run the module, compare the output.
# ======================================================================
TT_HDR='service_date,trip_id,route_id,stop_id,stop_sequence,scheduled_arrival_utc'
LV_HDR='service_date,trip_id,vehicle_id,stop_id,stop_sequence,actual_arrival_utc,confidence'
OUT_HDR='service_date,trip_id,route_id,vehicle_id,stop_id,stop_sequence,scheduled_arrival_utc,actual_arrival_utc,delay_min,status,confidence'
run_case() {   # uses $TT_ROWS and $LV_ROWS; writes $TMP/c_out.csv and $TMP/c_err.txt
  printf '%s\n%s\n' "$TT_HDR" "$TT_ROWS" > "$TMP/c_tt.csv"
  printf '%s\n%s\n' "$LV_HDR" "$LV_ROWS" > "$TMP/c_lv.csv"
  "$SCRIPT" "$TMP/c_tt.csv" "$TMP/c_lv.csv" "$TMP/c_out.csv" >/dev/null 2> "$TMP/c_err.txt"
}
assert_out() {  # $1 label, $2 expected data rows (header is added)
  printf '%s\n%s\n' "$OUT_HDR" "$2" > "$TMP/c_exp.csv"
  diff -u "$TMP/c_exp.csv" "$TMP/c_out.csv" && ok "$1" || bad "$1"
}
assert_count() {  # $1 label, $2 summary key, $3 expected value
  grep -qx "$2=$3" "$TMP/c_err.txt" && ok "$1" || bad "$1 (expected $2=$3, got: $(grep "^$2=" "$TMP/c_err.txt"))"
}

# ---- Checklist: Test early arrivals -----------------------------------
TT_ROWS='2026-05-01,E1,R1,S1,1,2026-05-01T10:00:00Z
2026-05-01,E1,R1,S2,2,2026-05-01T10:10:00Z
2026-05-01,E1,R1,S3,3,2026-05-01T10:20:00Z'
LV_ROWS='2026-05-01,E1,0042,S1,1,2026-05-01T09:59:30Z,high
2026-05-01,E1,0042,S2,2,2026-05-01T10:05:00Z,high
2026-05-01,E1,0042,S3,3,2026-05-01T10:00:00Z,medium'
run_case
assert_out "[early] early arrivals give negative delay_min and ON_TIME (-0.50, -5.00, -20.00)" \
'2026-05-01,E1,R1,0042,S1,1,2026-05-01T10:00:00Z,2026-05-01T09:59:30Z,-0.50,ON_TIME,high
2026-05-01,E1,R1,0042,S2,2,2026-05-01T10:10:00Z,2026-05-01T10:05:00Z,-5.00,ON_TIME,high
2026-05-01,E1,R1,0042,S3,3,2026-05-01T10:20:00Z,2026-05-01T10:00:00Z,-20.00,ON_TIME,medium'

# ---- Checklist: Test midnight-crossing timestamps ----------------------
TT_ROWS='2026-05-01,M1,R2,S1,1,2026-05-01T23:58:00Z
2026-05-01,M1,R2,S2,2,2026-05-02T00:03:00Z
2026-12-31,M2,R2,S1,1,2026-12-31T23:59:00Z
2028-02-28,M3,R2,S1,1,2028-02-28T23:50:00Z
2028-02-29,M4,R2,S1,1,2028-02-29T23:55:00Z
2027-02-28,M5,R2,S1,1,2027-02-28T23:55:00Z
2100-02-28,M6,R2,S1,1,2100-02-28T23:55:00Z
2000-02-29,M7,R2,S1,1,2000-02-29T23:55:00Z'
LV_ROWS='2026-05-01,M1,0100,S1,1,2026-05-02T00:04:00Z,high
2026-05-01,M1,0100,S2,2,2026-05-01T23:59:00Z,high
2026-12-31,M2,0101,S1,1,2027-01-01T00:20:00Z,high
2028-02-28,M3,0102,S1,1,2028-02-29T00:10:00Z,high
2028-02-29,M4,0103,S1,1,2028-03-01T00:05:00Z,high
2027-02-28,M5,0104,S1,1,2027-03-01T00:05:00Z,high
2100-02-28,M6,0105,S1,1,2100-03-01T00:05:00Z,high
2000-02-29,M7,0106,S1,1,2000-03-01T00:05:00Z,high'
run_case
assert_out "[midnight] late/early across midnight, year end, Feb->Mar in leap (2028), non-leap (2027), 2100 and 2000" \
'2026-05-01,M1,R2,0100,S1,1,2026-05-01T23:58:00Z,2026-05-02T00:04:00Z,6.00,DELAYED,high
2026-05-01,M1,R2,0100,S2,2,2026-05-02T00:03:00Z,2026-05-01T23:59:00Z,-4.00,ON_TIME,high
2026-12-31,M2,R2,0101,S1,1,2026-12-31T23:59:00Z,2027-01-01T00:20:00Z,21.00,MAJOR_DELAY,high
2028-02-28,M3,R2,0102,S1,1,2028-02-28T23:50:00Z,2028-02-29T00:10:00Z,20.00,MAJOR_DELAY,high
2028-02-29,M4,R2,0103,S1,1,2028-02-29T23:55:00Z,2028-03-01T00:05:00Z,10.00,DELAYED,high
2027-02-28,M5,R2,0104,S1,1,2027-02-28T23:55:00Z,2027-03-01T00:05:00Z,10.00,DELAYED,high
2100-02-28,M6,R2,0105,S1,1,2100-02-28T23:55:00Z,2100-03-01T00:05:00Z,10.00,DELAYED,high
2000-02-29,M7,R2,0106,S1,1,2000-02-29T23:55:00Z,2000-03-01T00:05:00Z,10.00,DELAYED,high'

# ---- Checklist: Test invalid timestamps --------------------------------
TT_ROWS='2026-05-01,T1,R1,S1,1,2026-05-01T10:00:00Z
2026-05-01,T2,R1,S1,1,not-a-time'
LV_ROWS='2026-05-01,T1,0200,S1,1,2026-05-01T10:03:00Z,high
2026-05-01,T1,0200,S1,1,04.56AM,high
2026-05-01,T1,0200,S1,1,2026-05-01 10:03:00,high
2026-05-01,T1,0200,S1,1,2026-05-01T25:00:00Z,high
2026-05-01,T1,0200,S1,1,2026-13-01T10:00:00Z,high
2026-05-01,T1,0200,S1,1,2026-05-01T10:03:00,high
2026-05-01,T1,0200,S1,1,2026-05-01T10:03:00+05:30,high'
run_case
assert_out "[invalid timestamp] only the valid live row is written" \
'2026-05-01,T1,R1,0200,S1,1,2026-05-01T10:00:00Z,2026-05-01T10:03:00Z,3.00,ON_TIME,high'
assert_count "[invalid timestamp] 6 bad live timestamps rejected" live_rejected_bad_timestamp 6
assert_count "[invalid timestamp] bad scheduled timestamp rejected from timetable" timetable_rows_rejected 1

# ---- Checklist: Test missing identifiers --------------------------------
TT_ROWS='2026-05-01,T1,R1,S1,1,2026-05-01T10:00:00Z
,T9,R1,S1,1,2026-05-01T10:00:00Z'
LV_ROWS='2026-05-01,T1,0300,S1,1,2026-05-01T10:02:00Z,high
2026-05-01,,0300,S1,1,2026-05-01T10:02:00Z,high
2026-05-01,T1,,S1,1,2026-05-01T10:02:00Z,high
2026-05-01,T1,0300,,1,2026-05-01T10:02:00Z,high
,T1,0300,S1,1,2026-05-01T10:02:00Z,high
2026-05-01,T1,0300,S1,,2026-05-01T10:02:00Z,high
2026-05-01,T1,0300,S1,1,2026-05-01T10:02:00Z'
run_case
assert_out "[missing id] only the complete live row is written" \
'2026-05-01,T1,R1,0300,S1,1,2026-05-01T10:00:00Z,2026-05-01T10:02:00Z,2.00,ON_TIME,high'
assert_count "[missing id] 5 live rows with an empty identifier rejected" live_rejected_empty_field 5
assert_count "[missing id] live row with a missing column rejected" live_rejected_bad_field_count 1
assert_count "[missing id] timetable row with empty trip_id rejected" timetable_rows_rejected 1

# ---- Checklist: Test duplicate records ----------------------------------
TT_ROWS='2026-05-01,D1,R1,S1,1,2026-05-01T10:00:00Z
2026-05-01,D2,R1,S1,1,2026-05-01T10:00:00Z
2026-05-01,D3,R1,S1,1,2026-05-01T10:00:00Z
2026-05-01,D4,R1,S1,1,2026-05-01T10:00:00Z
2026-05-01,D1,R1,S1,1,2026-05-01T11:00:00Z'
LV_ROWS='2026-05-01,D1,0400,S1,1,2026-05-01T10:09:00Z,high
2026-05-01,D1,0400,S1,1,2026-05-01T10:01:00Z,medium
2026-05-01,D2,0401,S1,1,2026-05-01T10:02:00Z,medium
2026-05-01,D2,0401,S1,1,2026-05-01T10:03:00Z,high
2026-05-01,D3,0402,S1,1,2026-05-01T10:04:00Z,medium
2026-05-01,D3,0402,S1,1,2026-05-01T10:06:00Z,medium
2026-05-01,D4,0403,S1,1,2026-05-01T10:20:00Z,high
2026-05-01,D4,0403,S1,1,2026-05-01T10:16:00Z,high'
run_case
assert_out "[duplicate] high beats medium (either order); on a tie the later row wins; first timetable row wins" \
'2026-05-01,D1,R1,0400,S1,1,2026-05-01T10:00:00Z,2026-05-01T10:09:00Z,9.00,DELAYED,high
2026-05-01,D2,R1,0401,S1,1,2026-05-01T10:00:00Z,2026-05-01T10:03:00Z,3.00,ON_TIME,high
2026-05-01,D3,R1,0402,S1,1,2026-05-01T10:00:00Z,2026-05-01T10:06:00Z,6.00,DELAYED,medium
2026-05-01,D4,R1,0403,S1,1,2026-05-01T10:00:00Z,2026-05-01T10:16:00Z,16.00,MAJOR_DELAY,high'
assert_count "[duplicate] 4 superseded live duplicates counted" live_duplicates_superseded 4
assert_count "[duplicate] duplicate timetable key ignored and counted" timetable_duplicates_ignored 1

# ---- Checklist: Verify threshold boundary cases -------------------------
TT_ROWS='2026-05-01,B1,R1,S1,1,2026-05-01T10:00:00Z
2026-05-01,B2,R1,S1,1,2026-05-01T10:00:00Z
2026-05-01,B3,R1,S1,1,2026-05-01T10:00:00Z
2026-05-01,B4,R1,S1,1,2026-05-01T10:00:00Z
2026-05-01,B5,R1,S1,1,2026-05-01T10:00:00Z
2026-05-01,B6,R1,S1,1,2026-05-01T10:00:00Z
2026-05-01,B7,R1,S1,1,2026-05-01T10:00:00Z'
LV_ROWS='2026-05-01,B1,0500,S1,1,2026-05-01T10:00:00Z,high
2026-05-01,B2,0500,S1,1,2026-05-01T10:04:59Z,high
2026-05-01,B3,0500,S1,1,2026-05-01T10:05:00Z,high
2026-05-01,B4,0500,S1,1,2026-05-01T10:05:01Z,high
2026-05-01,B5,0500,S1,1,2026-05-01T10:14:59Z,high
2026-05-01,B6,0500,S1,1,2026-05-01T10:15:00Z,high
2026-05-01,B7,0500,S1,1,2026-05-01T10:15:01Z,high'
run_case
assert_out "[boundary] 5/15 min: 0.00, 4.98, 5.00 ON_TIME | 5.02, 14.98 DELAYED | 15.00, 15.02 MAJOR_DELAY" \
'2026-05-01,B1,R1,0500,S1,1,2026-05-01T10:00:00Z,2026-05-01T10:00:00Z,0.00,ON_TIME,high
2026-05-01,B2,R1,0500,S1,1,2026-05-01T10:00:00Z,2026-05-01T10:04:59Z,4.98,ON_TIME,high
2026-05-01,B3,R1,0500,S1,1,2026-05-01T10:00:00Z,2026-05-01T10:05:00Z,5.00,ON_TIME,high
2026-05-01,B4,R1,0500,S1,1,2026-05-01T10:00:00Z,2026-05-01T10:05:01Z,5.02,DELAYED,high
2026-05-01,B5,R1,0500,S1,1,2026-05-01T10:00:00Z,2026-05-01T10:14:59Z,14.98,DELAYED,high
2026-05-01,B6,R1,0500,S1,1,2026-05-01T10:00:00Z,2026-05-01T10:15:00Z,15.00,MAJOR_DELAY,high
2026-05-01,B7,R1,0500,S1,1,2026-05-01T10:00:00Z,2026-05-01T10:15:01Z,15.02,MAJOR_DELAY,high'
# Same boundaries with decimal thresholds (2.5 and 7.5 minutes = 150 s and 450 s)
printf 'ON_TIME_MAX_MIN=2.5\nMAJOR_DELAY_MIN=7.5\n' > "$TMP/dec.conf"
LV_ROWS='2026-05-01,B1,0500,S1,1,2026-05-01T10:02:30Z,high
2026-05-01,B2,0500,S1,1,2026-05-01T10:02:31Z,high
2026-05-01,B3,0500,S1,1,2026-05-01T10:07:29Z,high
2026-05-01,B4,0500,S1,1,2026-05-01T10:07:30Z,high'
TT_ROWS='2026-05-01,B1,R1,S1,1,2026-05-01T10:00:00Z
2026-05-01,B2,R1,S1,1,2026-05-01T10:00:00Z
2026-05-01,B3,R1,S1,1,2026-05-01T10:00:00Z
2026-05-01,B4,R1,S1,1,2026-05-01T10:00:00Z'
CONFIG="$TMP/dec.conf" run_case
assert_out "[boundary] decimal thresholds 2.5/7.5: 2.50 ON_TIME | 2.52, 7.48 DELAYED | 7.50 MAJOR_DELAY" \
'2026-05-01,B1,R1,0500,S1,1,2026-05-01T10:00:00Z,2026-05-01T10:02:30Z,2.50,ON_TIME,high
2026-05-01,B2,R1,0500,S1,1,2026-05-01T10:00:00Z,2026-05-01T10:02:31Z,2.52,DELAYED,high
2026-05-01,B3,R1,0500,S1,1,2026-05-01T10:00:00Z,2026-05-01T10:07:29Z,7.48,DELAYED,high
2026-05-01,B4,R1,0500,S1,1,2026-05-01T10:00:00Z,2026-05-01T10:07:30Z,7.50,MAJOR_DELAY,high'

echo; echo "$pass passed, $fail failed"; [[ $fail -eq 0 ]]
