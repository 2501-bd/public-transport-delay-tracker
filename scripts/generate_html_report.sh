#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

REPORT="$ROOT/reports/summary_report.csv"
PROCESSED="$ROOT/data/processed_delays.csv"
TIMETABLE="$ROOT/data/timetable.csv"
UPDATES="$ROOT/data/live_updates.csv"
ALERT_LOG="$ROOT/logs/alerts.log"
CHART="$ROOT/reports/charts/average_delay_by_route.png"
OUTPUT="$ROOT/reports/daily_report.html"

for file in "$REPORT" "$PROCESSED" "$CHART"; do
    if [[ ! -f "$file" ]]; then
        echo "ERROR: Required file missing: $file" >&2
        exit 1
    fi
done

mkdir -p "$ROOT/reports"

OVERALL=$(awk -F',' 'NR==2 {print $0}' "$REPORT")
IFS=',' read -r TYPE ROUTE TOTAL AVG MAX ON_TIME DELAYED MAJOR <<< "$OVERALL"

ON_TIME_PERCENT=$(awk -v a="$ON_TIME" -v b="$TOTAL" \
    'BEGIN {if (b > 0) printf "%.2f", (a/b)*100; else print "0.00"}')

count_records() {
    if [[ -f "$1" ]]; then
        awk 'END {print (NR > 0 ? NR-1 : 0)}' "$1"
    else
        echo "0"
    fi
}

TIMETABLE_COUNT=$(count_records "$TIMETABLE")
UPDATE_COUNT=$(count_records "$UPDATES")
PROCESSED_COUNT=$(count_records "$PROCESSED")

LATEST_LOG=$(find "$ROOT/logs" -maxdepth 1 -type f \
    -name 'pipeline_*.log' -printf '%T@ %p\n' 2>/dev/null |
    sort -nr | head -1 | cut -d' ' -f2- || true)

if [[ -n "$LATEST_LOG" ]]; then
    PIPELINE_NAME=$(basename "$LATEST_LOG")
    if grep -q "Pipeline completed successfully" "$LATEST_LOG"; then
        PIPELINE_STATUS="Completed successfully"
        PIPELINE_CLASS="success"
    else
        PIPELINE_STATUS="Completion not confirmed"
        PIPELINE_CLASS="warning"
    fi
else
    PIPELINE_NAME="No pipeline log found"
    PIPELINE_STATUS="No execution recorded"
    PIPELINE_CLASS="warning"
fi

{
cat <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>TransitIQ | Operations Dashboard</title>

<style>
:root {
    --bg: #f4f6fa;
    --panel: #ffffff;
    --navy: #172554;
    --blue: #315efb;
    --text: #202b40;
    --muted: #78849a;
    --border: #e7ebf2;
    --green: #13865c;
    --red: #d94c4c;
    --shadow: 0 5px 22px rgba(25, 42, 75, 0.05);
}

* { box-sizing: border-box; }

body {
    margin: 0;
    font-family: Arial, Helvetica, sans-serif;
    background: var(--bg);
    color: var(--text);
}

.layout {
    display: flex;
    min-height: 100vh;
}

.sidebar {
    width: 245px;
    background: var(--navy);
    color: white;
    padding: 30px 20px;
    flex-shrink: 0;
}

.brand {
    font-size: 23px;
    font-weight: 800;
    letter-spacing: -0.7px;
    margin-bottom: 8px;
}

.brand span { color: #8ca8ff; }

.tagline {
    color: #aab7d3;
    font-size: 12px;
    margin-bottom: 42px;
}

.nav-label {
    color: #8998b9;
    font-size: 10px;
    letter-spacing: 1.5px;
    margin: 25px 10px 12px;
}

.nav a {
    display: block;
    padding: 12px 13px;
    margin: 5px 0;
    border-radius: 8px;
    color: #d5def2;
    text-decoration: none;
    font-size: 13px;
}

.nav a:hover, .nav a.active {
    background: #293c70;
    color: white;
}

.main {
    flex: 1;
    min-width: 0;
    padding: 32px;
}

.topbar {
    display: flex;
    justify-content: space-between;
    align-items: center;
    gap: 15px;
    margin-bottom: 28px;
}

h1 {
    margin: 0;
    font-size: 26px;
    letter-spacing: -0.6px;
}

.subtitle {
    color: var(--muted);
    font-size: 13px;
    margin-top: 7px;
}

.status {
    background: #e6f5ed;
    color: var(--green);
    padding: 9px 13px;
    border-radius: 20px;
    font-size: 12px;
    font-weight: bold;
    white-space: nowrap;
}

.section-title {
    font-size: 17px;
    margin: 30px 0 15px;
}

.cards {
    display: grid;
    grid-template-columns: repeat(4, minmax(0, 1fr));
    gap: 16px;
}

.card, .panel {
    background: var(--panel);
    border: 1px solid var(--border);
    border-radius: 13px;
    box-shadow: var(--shadow);
}

.card { padding: 20px; }

.card-label {
    color: var(--muted);
    font-size: 12px;
}

.card-value {
    font-size: 27px;
    font-weight: 750;
    margin: 12px 0 5px;
    letter-spacing: -0.8px;
}

.card-note {
    color: var(--muted);
    font-size: 11px;
}

.blue { color: var(--blue); }
.green { color: var(--green); }
.red { color: var(--red); }

.panel { padding: 22px; margin-bottom: 20px; }

.panel-heading {
    display: flex;
    justify-content: space-between;
    align-items: center;
    gap: 10px;
    margin-bottom: 18px;
}

.panel-heading h3 {
    font-size: 15px;
    margin: 0;
}

.panel-heading span {
    font-size: 11px;
    color: var(--muted);
}

.chart {
    width: 100%;
    max-height: 460px;
    object-fit: contain;
    display: block;
}

.table-wrap {
    overflow-x: auto;
}

table {
    width: 100%;
    border-collapse: collapse;
    font-size: 12px;
    white-space: nowrap;
}

th {
    background: #f5f7fb;
    color: #68758c;
    font-size: 10px;
    text-transform: uppercase;
    letter-spacing: 0.5px;
}

th, td {
    padding: 13px 12px;
    text-align: left;
    border-bottom: 1px solid var(--border);
}

tbody tr:hover { background: #f8faff; }

.search {
    padding: 10px 12px;
    border: 1px solid var(--border);
    border-radius: 8px;
    font-size: 12px;
    width: 220px;
    outline: none;
}

.search:focus { border-color: var(--blue); }

.pill {
    display: inline-block;
    padding: 5px 8px;
    border-radius: 20px;
    font-size: 10px;
    font-weight: bold;
}

.pill.success {
    background: #e5f5ed;
    color: var(--green);
}

.pill.warning {
    background: #fff1df;
    color: #b36b12;
}

.pill.danger {
    background: #fdeaea;
    color: var(--red);
}

.info-grid {
    display: grid;
    grid-template-columns: repeat(3, minmax(0, 1fr));
    gap: 15px;
}

.info-box {
    background: #f7f9fd;
    border-radius: 9px;
    padding: 17px;
}

.info-label {
    color: var(--muted);
    font-size: 11px;
}

.info-value {
    font-size: 20px;
    font-weight: bold;
    margin-top: 8px;
}

.footer {
    color: var(--muted);
    text-align: center;
    font-size: 11px;
    padding: 25px 0 5px;
}

@media(max-width: 1050px) {
    .cards { grid-template-columns: repeat(2, 1fr); }
}

@media(max-width: 700px) {
    .layout { display: block; }
    .sidebar { width: 100%; padding: 20px; }
    .tagline { margin-bottom: 15px; }
    .nav { display: flex; flex-wrap: wrap; }
    .nav-label { display: none; }
    .nav a { padding: 9px; }
    .main { padding: 20px 14px; }
    .cards { grid-template-columns: 1fr 1fr; }
    .info-grid { grid-template-columns: 1fr; }
    .topbar { align-items: flex-start; flex-direction: column; }
}

@media(max-width: 400px) {
    .cards { grid-template-columns: 1fr; }
}
</style>
</head>

<body>
<div class="layout">

<aside class="sidebar">
    <div class="brand">Transit<span>IQ</span></div>
    <div class="tagline">PUBLIC TRANSPORT INTELLIGENCE</div>

    <div class="nav-label">WORKSPACE</div>
    <nav class="nav">
        <a class="active" href="#overview">Overview</a>
        <a href="#analytics">Route Analytics</a>
        <a href="#routes">Route Performance</a>
        <a href="#alerts">Alert Centre</a>
    </nav>

    <div class="nav-label">SYSTEM</div>
    <nav class="nav">
        <a href="#data">Data Ingestion</a>
        <a href="#pipeline">Pipeline Activity</a>
    </nav>
</aside>

<main class="main">

<header class="topbar">
    <div>
        <h1>Operations Overview</h1>
        <div class="subtitle">
            Public transport punctuality and delay monitoring
        </div>
    </div>
    <div class="status">● Generated report</div>
</header>

<section id="overview">
    <div class="section-title">Network Performance</div>

    <div class="cards">
        <div class="card">
            <div class="card-label">Total Stop Records</div>
            <div class="card-value">$TOTAL</div>
            <div class="card-note">Processed records</div>
        </div>

        <div class="card">
            <div class="card-label">Average Delay</div>
            <div class="card-value blue">$AVG <small>min</small></div>
            <div class="card-note">Across all records</div>
        </div>

        <div class="card">
            <div class="card-label">On-Time Performance</div>
            <div class="card-value green">$ON_TIME_PERCENT%</div>
            <div class="card-note">$ON_TIME on-time records</div>
        </div>

        <div class="card">
            <div class="card-label">Major-Delay Records</div>
            <div class="card-value red">$MAJOR</div>
            <div class="card-note">Delay of 15 minutes or more</div>
        </div>
    </div>

    <div class="cards" style="margin-top:16px">
        <div class="card">
            <div class="card-label">Maximum Delay</div>
            <div class="card-value">$MAX <small>min</small></div>
            <div class="card-note">Highest recorded delay</div>
        </div>
        <div class="card">
            <div class="card-label">Delayed Records</div>
            <div class="card-value">$DELAYED</div>
            <div class="card-note">Includes major delays</div>
        </div>
        <div class="card">
            <div class="card-label">Routes Analysed</div>
            <div class="card-value">$(awk -F',' 'NR>2 {n++} END {print n+0}' "$REPORT")</div>
            <div class="card-note">Routes in summary report</div>
        </div>
        <div class="card">
            <div class="card-label">Alert Threshold</div>
            <div class="card-value">15 <small>min</small></div>
            <div class="card-note">Major-delay classification</div>
        </div>
    </div>
</section>

<section id="analytics">
    <div class="section-title">Route Analytics</div>
    <div class="panel">
        <div class="panel-heading">
            <h3>Average Delay by Route</h3>
            <span>GNUplot generated</span>
        </div>
        <img class="chart" src="charts/average_delay_by_route.png"
             alt="Average delay by route">
    </div>
</section>

<section id="routes">
    <div class="section-title">Route Performance</div>
    <div class="panel">
        <div class="panel-heading">
            <h3>Route-wise Statistics</h3>
            <input id="routeSearch" class="search"
                   type="search" placeholder="Search route...">
        </div>

        <div class="table-wrap">
        <table id="routeTable">
            <thead>
            <tr>
                <th>Route</th>
                <th>Records</th>
                <th>Avg Delay</th>
                <th>Max Delay</th>
                <th>On Time</th>
                <th>Delayed</th>
                <th>Major Delays</th>
            </tr>
            </thead>
            <tbody>
EOF

awk -F',' 'NR>2 {
    printf "<tr><td>%s</td><td>%s</td><td>%s min</td><td>%s min</td><td>%s</td><td>%s</td><td>%s</td></tr>\n",
    $2,$3,$4,$5,$6,$7,$8
}' "$REPORT"

cat <<EOF
            </tbody>
        </table>
        </div>
    </div>
</section>

<section id="alerts">
    <div class="section-title">Alert Centre</div>
    <div class="panel">
        <div class="panel-heading">
            <h3>Major-Delay Records</h3>
            <span class="pill danger">$MAJOR records ≥ 15 min</span>
        </div>

        <div class="table-wrap">
        <table id="alertTable">
            <thead>
            <tr>
                <th>Service Date</th>
                <th>Route</th>
                <th>Trip ID</th>
                <th>Vehicle</th>
                <th>Stop</th>
                <th>Delay</th>
            </tr>
            </thead>
            <tbody>
EOF

awk -F',' '
NR==1 {
    for (i=1;i<=NF;i++) col[$i]=i
    next
}
$(col["status"])=="MAJOR_DELAY" {
    printf "<tr><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td><span class=\"pill danger\">%s min</span></td></tr>\n",
    $(col["service_date"]), $(col["route_id"]),
    $(col["trip_id"]), $(col["vehicle_id"]),
    $(col["stop_id"]), $(col["delay_min"])
}' "$PROCESSED"

cat <<EOF
            </tbody>
        </table>
        </div>
    </div>
</section>

<section id="data">
    <div class="section-title">Data Ingestion</div>
    <div class="panel">
        <div class="panel-heading">
            <h3>Dataset Status</h3>
            <span>Generated file counts</span>
        </div>

        <div class="info-grid">
            <div class="info-box">
                <div class="info-label">Timetable Records</div>
                <div class="info-value">$TIMETABLE_COUNT</div>
            </div>
            <div class="info-box">
                <div class="info-label">Update Records</div>
                <div class="info-value">$UPDATE_COUNT</div>
            </div>
            <div class="info-box">
                <div class="info-label">Processed Records</div>
                <div class="info-value">$PROCESSED_COUNT</div>
            </div>
        </div>
    </div>
</section>

<section id="pipeline">
    <div class="section-title">Pipeline Activity</div>
    <div class="panel">
        <div class="panel-heading">
            <h3>Latest Execution</h3>
            <span class="pill $PIPELINE_CLASS">$PIPELINE_STATUS</span>
        </div>
        <div class="info-box">
            <div class="info-label">Latest pipeline log</div>
            <div class="info-value" style="font-size:14px">$PIPELINE_NAME</div>
        </div>
EOF

if [[ -n "$LATEST_LOG" ]]; then
    echo '<h4>Recent pipeline output</h4>'
    echo '<pre style="white-space:pre-wrap;overflow-wrap:anywhere;font-size:11px;color:#68758c;background:#f7f9fd;padding:15px;border-radius:8px">'
    tail -15 "$LATEST_LOG" | sed 's/</\&lt;/g; s/>/\&gt;/g'
    echo '</pre>'
fi

cat <<'EOF'
    </div>
</section>

<div class="footer">
    TransitIQ · Public Transport Delay Monitoring System<br>
    Report generated from local project datasets. Historical data, not live tracking.
</div>

</main>
</div>

<script>
const routeSearch = document.getElementById("routeSearch");

routeSearch.addEventListener("input", function () {
    const query = this.value.toLowerCase();

    document.querySelectorAll("#routeTable tbody tr").forEach(row => {
        row.style.display = row.innerText.toLowerCase().includes(query)
            ? ""
            : "none";
    });
});
</script>

</body>
</html>
EOF
} > "$OUTPUT"

echo "Dashboard generated: $OUTPUT"
