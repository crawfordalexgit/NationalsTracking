# Minimal Get-TopSwimmersChart.ps1 — create a minimal chart fragment and write debug artifacts
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$cache = Join-Path $root 'swimmer_cache.json'
if (-not (Test-Path $cache)) { Write-Error "Cache missing at $cache"; exit 1 }
$swimmers = Get-Content $cache -Raw | ConvertFrom-Json

# number of top swimmers to consider for virtual ranking/outputs
$TopN = 50

# helper: convert mm:ss.xx to seconds
function TimeToSeconds($t) {
    if (-not $t) { return $null }
    $parts = $t -split ':'
    if ($parts.Count -eq 2) { return ([double]$parts[0]*60) + [double]$parts[1] }
    if ($parts.Count -eq 3) { return ([double]$parts[0]*3600) + ([double]$parts[1]*60) + [double]$parts[2] }
    return $null
}

# Ensure Kieran Crawford is included (add if missing by searching rankings page)
if (-not ($swimmers | Where-Object { $_.Name -eq 'Kieran Crawford' })) {
    try {
        $rankingsUrl = 'https://www.swimmingresults.org/12months/last12.php?Pool=L&Stroke=9&Sex=M&AgeGroup=13&date=31%2F12%2F2026&StartNumber=1&RecordsToView=100&Level=N&TargetNationality=E&TargetRegion=P'
        $html = (New-Object System.Net.WebClient).DownloadString($rankingsUrl)
        if ($html -match 'tiref=(\d+)[^\w\d]*[^>]*>\s*Kieran\s+Crawford') {
            $tid = $Matches[1]
            $sw = [PSCustomObject]@{ Name='Kieran Crawford'; Tiref = [int]$tid; LcTime = $null; HistoricalTimes = @() }
            $swimmers += $sw
            Write-Host "Added Kieran Crawford (tiref=$tid) to swimmer list"
        }
    } catch { Write-Warning "Could not add Kieran Crawford: $_" }
}

# Build datasets using HistoricalTimes (if present) else fall back to LcTime
$datasets = @()
foreach ($s in $swimmers) {
    $points = @()
    if ($s.HistoricalTimes -and $s.HistoricalTimes.Count -gt 0) {
        foreach ($e in ($s.HistoricalTimes | Where-Object { $_.Course -eq 'LC' } | Sort-Object @{Expression = { [datetime]$_.Date }})) {
            if (-not $e.PSObject.Properties.Match('Seconds') -and $e.Time) { $e | Add-Member -NotePropertyName Seconds -NotePropertyValue (TimeToSeconds($e.Time)) -Force }
            if ($e.Seconds -ne $null) { $points += @{ x = $e.Date; y = $e.Seconds; meet = ($e.Meet -or $e.MeetName -or '') ; time = ($e.Time -or '') } }
        }
    }
    # fallback to current LcTime if no historical LC points found
    if ($points.Count -eq 0 -and $s.LcTime) {
        $points += @{ x = (Get-Date -Format yyyy-MM-dd); y = TimeToSeconds($s.LcTime); meet = 'Rankings'; time = $s.LcTime }
    }
    $histCount = $points.Count
    if ($histCount -gt 0) {
        $ds = [PSCustomObject]@{ label = $s.Name; data = $points; tiref = $s.Tiref; historicalCount = $histCount }
        if ($s.Name -eq 'Kieran Crawford') {
            # make Kieran visually distinctive
            $ds | Add-Member -NotePropertyName borderColor -NotePropertyValue '#FFD166' -Force
            $ds | Add-Member -NotePropertyName borderWidth -NotePropertyValue 5 -Force
            $ds | Add-Member -NotePropertyName pointRadius -NotePropertyValue 14 -Force
            $ds | Add-Member -NotePropertyName pointStyle -NotePropertyValue 'rectRot' -Force
            $ds | Add-Member -NotePropertyName borderDash -NotePropertyValue @([int]6, [int]3) -Force
        }
        $datasets += $ds
    }
}

# Compute Kieran dashboard stats
$bestList = @()
foreach ($s in $swimmers) {
    $best = $null
    if ($s.HistoricalTimes -and $s.HistoricalTimes.Count -gt 0) {
        $vals = $s.HistoricalTimes | ForEach-Object { $_.Seconds } | Where-Object { $_ -ne $null }
        if ($vals) { $best = ($vals | Measure-Object -Minimum).Minimum }
    }
    if (-not $best -and $s.LcTime) { $best = TimeToSeconds($s.LcTime) }
    $bestList += [PSCustomObject]@{ Name = $s.Name; Best = $best }
}
$validBest = $bestList | Where-Object { $_.Best -ne $null } | Sort-Object Best
# rank of Kieran
$k = $validBest | Where-Object { $_.Name -eq 'Kieran Crawford' } | Select-Object -First 1
if ($k) {
    $names = $validBest | Select-Object -ExpandProperty Name
    $idx = [array]::IndexOf($names, $k.Name)
    if ($idx -ge 0) { $kRank = $idx + 1 } else { $kRank = $null }
} else { $kRank = $null }

# Try to compute an accurate rank from the rankings page (prefer explicit rank column). Try a few query variants (national then region) and pick the first match.
try {
    $hdrs = @{ 'User-Agent' = 'Mozilla/5.0 (Windows NT)'; 'Accept' = 'text/html' }
    $candidates = @(
        'https://www.swimmingresults.org/12months/last12.php?Pool=L&Stroke=9&Sex=M&AgeGroup=13&date=31%2F12%2F2026&StartNumber=1&RecordsToView=50&Level=N&TargetNationality=E&TargetRegion=P&TargetCounty=XXXX&TargetClub=XXXX',
        'https://www.swimmingresults.org/12months/last12.php?Pool=L&Stroke=9&Sex=M&AgeGroup=13&date=31%2F12%2F2026&StartNumber=1&RecordsToView=200&Level=N&TargetNationality=E'
    )
    foreach ($rankingsUrl in $candidates) {
        try {
            $resp = Invoke-WebRequest -Uri $rankingsUrl -Headers $hdrs -UseBasicParsing -ErrorAction Stop -TimeoutSec 30
            $html = $resp.Content
            # First try to capture explicit rank number from table rows: <tr> ... <td>RANK</td> ... <a>NAME</a>
            $rowPattern = '(?si)<tr[^>]*>.*?<td[^>]*>\s*(\d+)\s*</td>.*?<a[^>]*>([^<]+)</a>.*?</tr>'
            $rowMatches = [regex]::Matches($html, $rowPattern)
            foreach ($m in $rowMatches) {
                $ranknum = [int]$m.Groups[1].Value
                $name = ($m.Groups[2].Value).Trim() -replace '\s+', ' '
                if ($name -ieq 'Kieran Crawford') { $kRank = $ranknum; break }
            }
            if ($kRank) { Write-Host "Computed Kieran rank from ${rankingsUrl}: $kRank"; $rankingSource = $rankingsUrl; break }
            # fallback: use anchor order if explicit rank not found
            $pattern = '(?si)<a[^>]*tiref=(\d+)[^>]*>([^<]+)</a>'
            $matches = [regex]::Matches($html, $pattern)
            $pos = 0
            foreach ($m in $matches) {
                $pos++
                $name = ($m.Groups[2].Value).Trim() -replace '\s+', ' '
                if ($name -ieq 'Kieran Crawford') { $kRank = $pos; break }
            }
            if ($kRank) { Write-Host "Computed Kieran rank by anchor order from ${rankingsUrl}: $kRank"; $rankingSource = $rankingsUrl; break }
        } catch { Write-Warning "Rankings query failed for ${rankingsUrl}: $_" }
    }
} catch {
    Write-Warning "Could not fetch rankings page(s) to compute Kieran rank: $_"
}
# threshold for top-22 (22nd best)
$threshold = $null
if (($validBest).Count -ge 22) { $threshold = ($validBest | Select-Object -First 22 | Select-Object -Last 1).Best }
$kBest = if ($k) { [double]$k.Best } else { $null }
$gap = $null
if ($kBest -ne $null -and $threshold -ne $null) { $gap = [math]::Round($kBest - $threshold, 2) }
# helper format
function SecToTimeStr($s) { if ($s -eq $null) { return '' }; $m = [int]($s/60); $sec = [double]($s - ($m*60)); $mm = '{0:00}' -f $m; return ('{0}:{1:00.00}' -f $mm, $sec) }
$kStats = [PSCustomObject]@{
    Name = 'Kieran Crawford'
    BestSeconds = $kBest
    BestTime = SecToTimeStr($kBest)
    Rank = $kRank
    HistoricalCount = ($swimmers | Where-Object { $_.Name -eq 'Kieran Crawford' } | Select-Object -ExpandProperty HistoricalCount)
    ThresholdSeconds = $threshold
    ThresholdTime = if ($threshold) { SecToTimeStr($threshold) } else { '' }
    GapSeconds = $gap
    Needs = if ($gap -gt 0) { ('Needs {0} s to reach {1}th' -f $gap, $TopN) } elseif ($gap -le 0) { ('Currently inside Top {0}' -f $TopN) } else { '' }
}
$kieranStatsJson = $kStats | ConvertTo-Json -Depth 6

$datasetsJson = $datasets | ConvertTo-Json -Depth 20
$datasetsBase64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($datasetsJson))

# Write debug artifacts
$debugDir = Join-Path (Split-Path $root -Parent) 'debug'
if (-not (Test-Path $debugDir)) { New-Item -ItemType Directory -Path $debugDir | Out-Null }
$debugFragmentPath = Join-Path $debugDir 'debug_generated_chart_fragment.html'

# Build full HTML with Chart.js, filters, and UI
$outHtml = @"
<!doctype html>
<html>
<head>
<meta charset='utf-8'>
<title>Top 50 13yo 200m Breaststroke</title>
<style>/* Minimal normalize to avoid external dependency */
html,body{margin:0;padding:0;border:0;font-family:system-ui,-apple-system,Segoe UI,Roboto,Arial,sans-serif;background:#111;color:#ddd}
*,*::before,*::after{box-sizing:border-box}
</style>
<style>
body { font-family: Arial, sans-serif; margin: 20px; background: #0b1220; color: #eee }
h1 { margin-bottom: 10px }
#controls { display:flex; gap: 20px; align-items:flex-start; margin-bottom: 12px }
#swimmer-filters { max-height: 320px; overflow:auto; padding: 6px; background: #0f1724; border-radius:6px }
.filter-item { display:flex; align-items:center; gap:8px; margin:4px 0 }
.filter-item label { cursor:pointer }
#chart-wrap { background: #071024; padding:12px; border-radius:8px }
#recent-changes { margin-top: 16px; color: #fff; background:#07203a; padding:10px; border-radius:6px }
#recent-changes h3 { margin:0 0 6px 0 }
.button { background: #1f6feb; color: #fff; border:none; padding:6px 10px; border-radius:4px; cursor:pointer }
.button.toggle-active { background: #0ea5a5 }
.small { font-size: 0.9em }
/* Rankings table */
.rank-table { width: 100%; border-collapse: collapse; margin-top:8px }
.rank-table th, .rank-table td { padding:6px 8px; border-bottom: 1px solid rgba(255,255,255,0.05); text-align:left; }
.rank-table th { color: #FFD166; font-size:0.9em }
.rank-month { margin-top:12px; background:#071024; padding:8px; border-radius:6px }
.rank-slow { color:#faa }
.rank-fast { color:#8BE38B }
/* Highlight the time used for ranking */
.time-used { background: rgba(255,209,102,0.06); font-weight:700; border-radius:4px; padding:2px 6px; }
/* Annotate Kieran row */
.kieran-row td { border-left: 3px solid #FFD166; }
</style>
<!-- Chart.js (prefer local copy to avoid CDN blocking) -->
<script src='chart.min.js'></script>
<script src='chart-shims.js'></script>
</head>
<body>
<h1>Top 50 13yo 200m Breaststroke</h1>
<!-- Debug banner: visible when there are adapter/storage/JS errors -->
<div id='debug-banner' style='display:none;background:#3b0f0f;color:#fff;padding:10px;border-radius:6px;margin-bottom:12px;box-shadow:0 6px 18px rgba(0,0,0,0.6);font-family:monospace;white-space:pre-wrap;'></div>
<div id='top-dashboard' style='display:flex;gap:12px;align-items:center;margin-bottom:12px'>
  <div id='kieran-stats' style='background:linear-gradient(135deg,#07203a,#0f3b5a);padding:12px;border-radius:8px;box-shadow:0 4px 12px rgba(0,0,0,0.6);min-width:260px'></div>
  <div id='rank-summary' style='color:#ddd;font-size:0.95em'></div>
</div>
<div id='controls'>
  <div>
    <div class='small'>Filters</div>
    <div id='swimmer-filters'></div>
    <div style='margin-top:8px'>
      <button id='show-all' class='button small'>Show All</button>
      <button id='hide-all' class='button small'>Hide All</button>
      <button id='nextgen' class='button small'>NextGen (hide top 3)</button>
    </div>
  </div>
  <div style='flex:1'>
    <div id='chart-wrap' style='height:480px;'><canvas id='top22-chart' width='900' height='480' style='display:block; width:100%; height:480px'></canvas></div>

    <!-- Qualifying trend (Top-22 threshold) -->
    <div id='qual-chart-wrap' style='margin-top:16px;background:#071024;padding:12px;border-radius:8px'>
      <div style='display:flex;align-items:center;justify-content:space-between'>
        <div style='font-weight:bold;color:#FFD166'>Qualifying Trend <span id='qual-month-note' style='font-weight:normal;font-size:0.85em;color:#bbb;margin-left:10px' aria-live='polite'></span></div>
        <div style='display:flex;align-items:center;gap:12px'>
          <label style='font-size:0.9em;color:#ccc;display:flex;align-items:center;gap:8px'><input id='overlay-kieran' type='checkbox' checked/> Overlay Kieran <span style='font-size:0.8em;color:#bbb'>(default)</span></label>
          <label style='font-size:0.9em;color:#ccc;display:flex;align-items:center;gap:8px'><input id='show-monthly' type='checkbox' checked/> Show monthly 22nd <span style='font-size:0.8em;color:#bbb'>(default)</span></label>
          <button id='toggle-monthly-rankings' class='button small'>Hide monthly virtual rankings</button>
        </div>
      </div>
      <div style='height:220px; margin-top:10px;'><canvas id='qual-chart' width='900' height='220' style='display:block; width:100%; height:220px'></canvas></div>
      <div id='monthly-rankings' style='margin-top:12px;'></div>
      </div>
    </div>
    <div id='legend' style='margin-top:8px; display:flex; flex-wrap:wrap; gap:8px'></div>
  </div>
</div>

<div id='recent-changes'>
  <h3>Recent Ranking Changes</h3>
  <div class='small'>21/09/25 to 22/11/25</div>
  <div id='movers'></div>
</div>

<script>
// datasets injected from PowerShell as base64
var datasetsBase64 = '$datasetsBase64';
// Top-N used for virtual rankings and monthly computations
var TOP_N = $TopN;
var datasets = JSON.parse(atob(datasetsBase64));
console.log('datasets parsed count:', datasets.length);
// assign colors and normalize dates robustly
function parseDateValue(v){
  if (!v && v !== 0) { return null }
  // numeric timestamp
  if (typeof v === 'number') { var d = new Date(v); return isNaN(d.getTime())? null : d }
  if (typeof v === 'string') {
    var s = v.trim();
    // ISO-like yyyy-mm-dd or yyyy-mm-ddTHH:MM
    if (/^\d{4}-\d{2}-\d{2}(T|$)/.test(s)) { var d = new Date(s); if (!isNaN(d.getTime())) { return d } }
    // try Date.parse directly
    var p = Date.parse(s);
    if (!isNaN(p)) { return new Date(p) }
    // try dd/mm/yy or dd/mm/yyyy
    var m = s.match(/^(\d{1,2})\/(\d{1,2})\/(\d{2,4})$/);
    if (m) {
      var day = parseInt(m[1],10), mon = parseInt(m[2],10)-1, yr = parseInt(m[3],10);
      if (yr < 100) { yr += 2000 }
      var d2 = new Date(yr, mon, day);
      if (!isNaN(d2.getTime())) { return d2 }
    }
    // give up
    return null
  }
  return null
}

// helper: format seconds as mm:ss.00 (used by tooltips and y-axis tick formatting)
function secondsToTime(s){
  if (s === null || s === undefined || isNaN(s)) return '';
  var mins = Math.floor(s/60);
  var secs = (s - mins*60).toFixed(2);
  var mm = ('00'+mins).slice(-2);
  // ensure leading 0 on single-digit seconds like '3.45' -> '03.45'
  if (secs.indexOf('.') === 1) { secs = '0' + secs }
  return mm + ':' + secs;
}

datasets.forEach(function(d,i){
  var hue = Math.round((i * 360 / datasets.length) % 360);
  // respect server-provided color for special swimmers (Kieran)
  if (!d.borderColor) { d.borderColor = 'hsl('+hue+',70%,60%)' }
  d.backgroundColor = d.borderColor;
  d.fill = false;
  if (!('pointRadius' in d)) { d.pointRadius = 10 }
  d.pointHoverRadius = d.pointHoverRadius || (d.pointRadius + 2);
  d.pointBackgroundColor = d.pointBackgroundColor || '#fff';
  d.pointBorderColor = d.pointBorderColor || '#000';
  d.borderWidth = d.borderWidth || 3;
  d.tension = 0.0;

  // normalize and filter invalid dates
  var originalCount = d.data.length || 0;
  var mapped = (d.data || []).map(function(p){
    var dt = parseDateValue(p.x);
    return { orig: p, x: dt, y: p.y, meet: (p.meet||p.Meet||null), timeStr: (p.time||p.Time||null) }
  });
  var valid = mapped.filter(function(p){ return p.x && !isNaN(p.x.getTime()) && (typeof p.y === 'number') });
  var removed = originalCount - valid.length;
  d.data = valid.map(function(p){ return { x: p.x.getTime(), y: p.y, meet: p.meet, time: p.timeStr } });
  // update historicalCount to match actual points
  d.historicalCount = d.data.length;
  console.log('dataset', i, d.label, 'original=', originalCount, 'kept=', d.data.length, 'removed=', removed, 'sample=', (d.data[0]? new Date(d.data[0].x).toISOString().slice(0,10) + '|' + d.data[0].y : 'none'));
});
// show debug list of dataset counts
var debugList = datasets.map(function(d){ return d.label + ' (' + (d.historicalCount||d.data.length||0) + ')' }).join(', ');
console.log('Dataset overview:', debugList);
try { document.getElementById('chart-wrap').insertAdjacentHTML('afterend', "<div id='debug-list' style='color:#ddd;margin-top:10px'>Datasets: " + debugList + "</div>"); } catch(e) { console.log('Could not insert debug-list:', e) }

// Debug banner helpers: collect messages and display them in the visible banner
var debugMessages = [];
function showDebugBanner(msgs){
  try{
    var el = document.getElementById('debug-banner'); if (!el) return;
    if (!msgs || msgs.length === 0){ el.style.display='none'; return }
    var lines = msgs.map(function(m){ return m; }).join('\n');
    // include ranking source when available
    if (typeof rankingSource !== 'undefined' && rankingSource) { lines = 'Ranking source: ' + rankingSource + '\n' + lines }
    el.textContent = lines; el.style.display = 'block';
  }catch(e){ console.log('Could not show debug banner:', e) }
}

// Wrap console.error/warn to capture messages
(function(){
  var _err = console.error.bind(console); var _warn = console.warn.bind(console);
  console.error = function(){ try{ _err.apply(console, arguments); debugMessages.push('ERROR: ' + Array.from(arguments).join(' ')); showDebugBanner(debugMessages); }catch(e){} };
  console.warn = function(){ try{ _warn.apply(console, arguments); debugMessages.push('WARN: ' + Array.from(arguments).join(' ')); showDebugBanner(debugMessages); }catch(e){} };
})();

// also ensure JS runtime errors are shown in banner
window.onerror = function(msg, src, ln, col, err) { try{ var text = 'JS Error: ' + msg + ' at ' + src + ':' + ln + ':' + col; debugMessages.push(text); showDebugBanner(debugMessages); }catch(e){}; var el = document.getElementById('debug-errors'); if (!el) { el = document.createElement('div'); el.id='debug-errors'; el.style.color='red'; el.style.marginTop='8px'; document.body.insertBefore(el, document.body.firstChild); } el.innerText = 'JS Error: ' + msg + ' at ' + src + ':' + ln + ':' + col; return false }

// move Kieran to top (drawn last) so it appears above others
var kidx = datasets.findIndex(function(d){ return d.label === 'Kieran Crawford' });
if (kidx >= 0) {
  var kdat = datasets.splice(kidx,1)[0];
  datasets.push(kdat);
}

// render Kieran stats block if provided
var rankingSource = '$rankingSource';
var kieranStats = $kieranStatsJson ? $kieranStatsJson : null;
try {
  if (kieranStats) {
    var ks = JSON.parse(JSON.stringify(kieranStats));
    var el = document.getElementById('kieran-stats');
    if (el) {
      el.innerHTML = "<div style='font-weight:bold;color:#FFD166;font-size:1.05em'>Kieran Crawford</div>" +
                     "<div style='margin-top:6px;font-size:1.4em;font-weight:bold;color:#fff'>" + (ks.BestTime||'N/A') + "</div>" +
                     "<div class='small' style='opacity:0.85'>Best • " + (ks.HistoricalCount||0) + " swims</div>" +
                     "<div style='margin-top:8px;font-size:0.95em'>Rank: <strong style='font-size:1.2em;color:#FFD166'>" + (ks.Rank||'N/A') + "</strong></div>" +
                     "<div class='small' style='margin-top:6px'>" + (ks.ThresholdTime? ("22nd: <strong>"+ks.ThresholdTime+"</strong> • Gap: <strong>"+(ks.GapSeconds>0? '+'+ks.GapSeconds+'s':'0s')+"</strong>") : "") + "</div>" +
                     "<div style='margin-top:8px'><button id='k-detail' class='button small'>Show Details</button></div>";
      document.getElementById('k-detail').addEventListener('click', function(){ alert('Kieran: ' + JSON.stringify(ks, null, 2)) });
    }
  }
} catch(e){ console.log('Could not render kieran stats:', e) }

// Verify date adapter is present and usable and install an inlined adapter if missing
(function(){
  var ok = false;
  try { ok = (typeof Chart !== 'undefined') && !!(Chart._adapters && Chart._adapters._date && typeof Chart._adapters._date.parse === 'function'); } catch(e){ ok = false }
  if (!ok) {
    var msg = 'Date adapter missing or incompatible. Inlining a built-in adapter with Intl-based formatting; for full feature parity install chartjs-adapter-date-fns UMD bundle.';
    if (!window.__adapterMissingLogged) { console.info(msg, (typeof Chart !== 'undefined' && Chart._adapters) ? Chart._adapters : null); window.__adapterMissingLogged = true; }
    if (!debugMessages.some(function(m){ return m && m.indexOf('Adapter:')===0; })) { debugMessages.push('Adapter: ' + msg); showDebugBanner(debugMessages); }

    // Build a more capable adapter that uses Intl for nicer formatting (covers Chart.js needs in this project)
    var inlinedAdapter = {
      _id: 'inlined-intl-adapter',
      formats: function(){ return { datetime: 'PPpp', millisecond:'HH:mm:ss.SSS', second:'HH:mm:ss', minute:'HH:mm', hour:'HH:mm', day:'MMM d', week:'PP', month:'MMM yyyy', quarter:'qqq - yyyy', year:'yyyy' }; },
      parse: function(value, format){ if (value === null) return null; if (typeof value === 'number') return value; if (value instanceof Date) return value.getTime(); if (typeof value === 'string'){
          // try ISO and common formats
          var t = Date.parse(value);
          if (!isNaN(t)) return t;
          // try dd/mm/yyyy
          var m = value.match(/^(\d{1,2})\/(\d{1,2})\/(\d{2,4})$/);
          if (m){ var day=+m[1], mon=+m[2]-1, yr=+m[3]; if (yr<100) yr+=2000; var d = new Date(yr,mon,day); if (!isNaN(d.getTime())) return d.getTime(); }
        }
        return null; },
      format: function(epoch, fmt){ try { var d = new Date(+epoch); if (!isFinite(d)) return String(epoch);
          // simple mapping for commonly-used format keys
          switch((fmt||'').toLowerCase()){
            case 'pppp':
            case 'pp':
            case 'ppppp':
            case 'ppp': return d.toLocaleString();
            case 'month':
            case 'mmm yyyy': return d.toLocaleDateString(undefined, { month:'short', year:'numeric' });
            case 'day':
            case 'mmm d': return d.toLocaleDateString(undefined, { month:'short', day:'2-digit' });
            case 'hour':
            case 'hh:mm': return d.toLocaleTimeString(undefined, { hour:'2-digit', minute:'2-digit' });
            case 'hh:mm:ss': return d.toLocaleTimeString();
            case 'yyyy': return d.getFullYear().toString();
            default: return d.toISOString(); }
        } catch(e){ return String(epoch); } },
      add: function(epoch, amount, unit){ var d = new Date(+epoch); switch(unit){ case 'millisecond': d.setMilliseconds(d.getMilliseconds()+amount); break; case 'second': d.setSeconds(d.getSeconds()+amount); break; case 'minute': d.setMinutes(d.getMinutes()+amount); break; case 'hour': d.setHours(d.getHours()+amount); break; case 'day': d.setDate(d.getDate()+amount); break; case 'week': d.setDate(d.getDate()+7*amount); break; case 'month': d.setMonth(d.getMonth()+amount); break; case 'quarter': d.setMonth(d.getMonth()+3*amount); break; case 'year': d.setFullYear(d.getFullYear()+amount); break; default: d.setMilliseconds(d.getMilliseconds()+amount); }
        return d.getTime(); },
      diff: function(a,b,unit){ var diff = (+a) - (+b); switch(unit){ case 'millisecond': return diff; case 'second': return Math.round(diff/1000); case 'minute': return Math.round(diff/60000); case 'hour': return Math.round(diff/3600000); case 'day': return Math.round(diff/86400000); case 'week': return Math.round(diff/(86400000*7)); case 'month': return (new Date(a).getUTCFullYear()-new Date(b).getUTCFullYear())*12 + (new Date(a).getUTCMonth()-new Date(b).getUTCMonth()); case 'quarter': return Math.floor(((new Date(a).getUTCMonth()/3)-(new Date(b).getUTCMonth()/3)) + (new Date(a).getUTCFullYear()-new Date(b).getUTCFullYear())*4); case 'year': return new Date(a).getUTCFullYear()-new Date(b).getUTCFullYear(); default: return diff; } },
      startOf: function(epoch, unit, isoWeekday){ var d = new Date(+epoch); switch(unit){ case 'year': d.setMonth(0,1); d.setHours(0,0,0,0); break; case 'quarter': var mq = Math.floor(d.getMonth()/3)*3; d.setMonth(mq,1); d.setHours(0,0,0,0); break; case 'month': d.setDate(1); d.setHours(0,0,0,0); break; case 'week': case 'isoweek': var day = d.getUTCDay(); var diff = (isoWeekday? (day===0?6:day-1) : day); d.setUTCDate(d.getUTCDate()-diff); d.setUTCHours(0,0,0,0); break; case 'day': d.setHours(0,0,0,0); break; case 'hour': d.setMinutes(0,0,0); break; case 'minute': d.setSeconds(0,0); break; case 'second': d.setMilliseconds(0); break; default: break; } return d.getTime(); },
      endOf: function(epoch, unit){ var d = new Date(inlinedAdapter.startOf(epoch, unit)); switch(unit){ case 'year': d.setFullYear(new Date(epoch).getFullYear()+1); d.setMilliseconds(d.getMilliseconds()-1); break; case 'quarter': d.setMonth(d.getMonth()+3); d.setMilliseconds(d.getMilliseconds()-1); break; case 'month': d.setMonth(d.getMonth()+1); d.setMilliseconds(d.getMilliseconds()-1); break; case 'week': d.setDate(d.getDate()+7); d.setMilliseconds(d.getMilliseconds()-1); break; case 'day': d.setDate(d.getDate()+1); d.setMilliseconds(d.getMilliseconds()-1); break; case 'hour': d.setHours(d.getHours()+1); d.setMilliseconds(d.getMilliseconds()-1); break; case 'minute': d.setMinutes(d.getMinutes()+1); d.setMilliseconds(d.getMilliseconds()-1); break; case 'second': d.setSeconds(d.getSeconds()+1); d.setMilliseconds(d.getMilliseconds()-1); break; default: d.setMilliseconds(d.getMilliseconds()-1); break; } return d.getTime(); },
      isValid: function(d){ return !isNaN(new Date(d).getTime()); }
    };

    function attemptInstallInline(){
      try {
        // IDEMPOTENT: avoid repeated installs/logging if already applied
        if (window.__inlinedAdapterInstalled) { return true; }
        if (typeof Chart !== 'undefined' && Chart._adapters && Chart._adapters._date && typeof Chart._adapters._date.override === 'function'){
          Chart._adapters._date.override(inlinedAdapter);
          window.__inlinedAdapterInstalled = true;
          console.info('Installed inlined Intl-based date adapter (inlined-intl-adapter). For full locale/format features install chartjs-adapter-date-fns.');
          if (document && document.body && !document.getElementById('adapter-info')){
            var el = document.createElement('div'); el.id='adapter-info'; el.style.color='#fff'; el.style.background='#2a4a38'; el.style.padding='8px'; el.style.borderRadius='6px'; el.style.marginBottom='8px'; el.innerText = 'INFO: Inlined date adapter installed (Intl-based). For full support, install chartjs-adapter-date-fns.'; document.body.insertBefore(el, document.body.firstChild);
          }
          return true;
        }
      } catch(e){ if (!window.__inlinedAdapterInstalled) { console.error('Failed to install inlined date adapter', e); } }
      return false;
    }

    if (!attemptInstallInline()){
      var attempts = 0; var maxAttempts = 40; var intervalId = setInterval(function(){ attempts++; if (attemptInstallInline() || attempts >= maxAttempts) { clearInterval(intervalId); } }, 250);
      window.addEventListener('load', attemptInstallInline); document.addEventListener('DOMContentLoaded', attemptInstallInline);
    }
  } else {
    console.log('Date adapter present and OK');
  }
})();

// capture JS errors and render them into the page for visibility
window.onerror = function(msg, src, ln, col, err) { var el = document.getElementById('debug-errors'); if (!el) { el = document.createElement('div'); el.id='debug-errors'; el.style.color='red'; el.style.marginTop='8px'; document.body.insertBefore(el, document.body.firstChild); } el.innerText = 'JS Error: ' + msg + ' at ' + src + ':' + ln + ':' + col; return false }

// Build chart (wrapped for dynamic loading)
function initTopChart(){
  var ctx = document.getElementById('top22-chart').getContext('2d');
  var topDatasets = datasets.slice(0,22);
  var kFull = datasets.find(function(d){ return d && d.label && d.label.toLowerCase().indexOf('kieran') !== -1; });
  if (kFull && topDatasets.indexOf(kFull) === -1){ topDatasets.push(kFull); }
  window.topChart = new Chart(ctx, {
    type: 'line',
    data: { datasets: topDatasets },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      interaction: { mode: 'nearest', intersect: true },

      plugins: {
        legend: { display: false },
        tooltip: {
          mode: 'nearest',
          intersect: true,
          callbacks: {
            title: function(items) { if (items && items.length) { return items[0].dataset.label + ' â€” ' + new Date(items[0].parsed.x).toISOString().slice(0,10); } return ''; },
            label: function(item) { var t = secondsToTime(item.parsed.y); var meta = (item.raw && (item.raw.meet || item.raw.time))?(' â€” ' + (item.raw.meet || item.raw.time)) : ''; return item.dataset.label + ': ' + t + meta; }
          }
        }
      },

      scales: {
        x: {
          type: 'linear',
          title: { display: true, text: 'Date' },
          ticks: { color: '#ddd', callback: function(value){ try{ return new Date(value).toISOString().slice(0,10); } catch(e) { return ''; } } }
        },
        y: { title: { display: true, text: 'Time (mm:ss.00)' }, ticks: { color: '#ddd', callback: function(value){ return secondsToTime(value) } } }
      }
    }
  });
  try { afterChartReady(); } catch(e) { console.error('afterChartReady failed', e) }
}

// ensure Chart.js is available, attempt local then CDN
function ensureChartLoadedAndInit(){
  if (window.Chart){ initTopChart(); return; }
  var s = document.createElement('script'); s.src='chart.min.js'; s.onload = function(){ if (window.Chart) { initTopChart(); } else { tryCdn(); } }; s.onerror = tryCdn; document.head.appendChild(s);
  function tryCdn(){ var s2 = document.createElement('script'); s2.src='https://cdn.jsdelivr.net/npm/chart.js'; s2.onload = function(){ if (window.Chart) initTopChart(); }; s2.onerror = function(){ debugMessages.push('Failed to load Chart.js (local & CDN)'); showDebugBanner(debugMessages); }; document.head.appendChild(s2); }
}
ensureChartLoadedAndInit();

function afterChartReady(){
  var topChart = window.topChart || null;
  // Build filter list and legend
  var filtersEl = document.getElementById('swimmer-filters');
  var legendEl = document.getElementById('legend');
  // hide any swimmer name lists/filters beneath the top chart (user requested no names below top graph)
  if (filtersEl) { filtersEl.style.display = 'none'; }
  if (legendEl) { legendEl.style.display = 'none'; }

  // compute and render the qualifying trend chart (Top-22 threshold over time)
  try {
    initQualChart();
    try { var monthly = computeMonthlyRankings(datasets); renderMonthlyRankings(monthly); } catch(e) { console.warn('monthly rankings render failed', e); }
    // wire monthly show/hide button
    try {
      var btn = document.getElementById('toggle-monthly-rankings');
      var cont = document.getElementById('monthly-rankings');
      if (btn && cont){
        // attach a stable handler and allow safe removal on re-init
        if (btn._toggleMonthlyRanksHandler) { btn.removeEventListener('click', btn._toggleMonthlyRanksHandler); }
        btn._toggleMonthlyRanksHandler = function(){
          if (cont.style.display === 'none' || cont.style.display === ''){ cont.style.display = 'block'; btn.innerText = 'Hide monthly virtual rankings'; } else { cont.style.display = 'none'; btn.innerText = 'Show monthly virtual rankings'; }
        };
        btn.addEventListener('click', btn._toggleMonthlyRanksHandler);
      }
    } catch(e){ console.warn('failed to install monthly ranking toggle', e); }
  } catch(e) { console.error('initQualChart failed', e) }

  // NOTE: Swimmer name filters/legend swatches removed (user requested no swimmer names below charts).
  // If you later want per-swimmer toggles, reintroduce a compact control UI here.



// Control buttons (no swimmer name elements are manipulated)
document.getElementById('show-all').addEventListener('click', function(){
  datasets.forEach(function(d,i){ topChart.getDatasetMeta(i).hidden = false; }); topChart.update();
});
document.getElementById('hide-all').addEventListener('click', function(){
  datasets.forEach(function(d,i){ topChart.getDatasetMeta(i).hidden = true; }); topChart.update();
});
var nextgenActive = false; document.getElementById('nextgen').addEventListener('click', function(e){
  nextgenActive = !nextgenActive; e.target.classList.toggle('toggle-active', nextgenActive);
  if (nextgenActive) {
    // hide top 3 (first 3 datasets)
    for (var i=0;i<datasets.length;i++){ var hide = (i<3); topChart.getDatasetMeta(i).hidden = hide; }
  } else { // restore
    for (var i=0;i<datasets.length;i++){ topChart.getDatasetMeta(i).hidden = false; }
  }
  topChart.update();
});

// Tooltip behaviour: already configured to show only hovered datapoint via intersect:true

// Movers and Shakers (placeholder - only at bottom)
var moversEl = document.getElementById('movers');
// sample content - keep it at bottom only
moversEl.innerHTML = '<div class="small">DOWN<br>Raditya Bimantara<br>1 position (2 to 3)</div>';

// Save debug fragment for inspection
  // generate debug fragment for inspection
  var fragment = '<!-- CHART_FRAGMENT -->\n' + '<div id="chart-area">' + document.getElementById('chart-wrap').innerHTML + '</div>';
  console.log('Generated chart fragment length:', fragment.length);
}
// Save debug fragment for inspection (will be generated after chart is ready inside afterChartReady)
// Compute Top-22 "qualifying" threshold series over time (month-only) and render a second chart below the main one
// For each calendar month, compute each swimmer's best within that month only and select the 22nd-best
function computeTop22MonthlyThresholds(datasets){ // fixed to 22nd rank (server-wide monthly line)
  var N = 22; // fixed N for monthly threshold
  // Build a list of all unique swim dates to determine month boundaries
  var dateSet = new Set();
  datasets.forEach(function(ds){ (ds.data||[]).forEach(function(p){ if (p && p.x) dateSet.add(p.x); }); });
  var dates = Array.from(dateSet).map(function(v){ return (typeof v==='number')? v : Date.parse(v); }).filter(function(v){ return !isNaN(v); });
  if (!dates.length) return [];
  // compute distinct month start epochs from earliest to latest
  dates.sort(function(a,b){ return a - b; });
  var first = new Date(dates[0]);
  var last = new Date(dates[dates.length-1]);
  var months = [];
  var cur = Date.UTC(first.getUTCFullYear(), first.getUTCMonth(), 1);
  var lastMonth = Date.UTC(last.getUTCFullYear(), last.getUTCMonth(), 1);
  while (cur <= lastMonth){ months.push(cur); cur = Date.UTC(new Date(cur).getUTCFullYear(), new Date(cur).getUTCMonth()+1, 1); }

  var out = [];
  months.forEach(function(mstart){
    var monthStart = mstart;
    var monthEnd = Date.UTC(new Date(mstart).getUTCFullYear(), new Date(mstart).getUTCMonth()+1, 1) - 1; // month end (ms)
    var vals = [];
    datasets.forEach(function(ds){
      var name = (ds.label || 'Unknown');
      var best = null;
      (ds.data||[]).forEach(function(p){
        try {
          if (!p || !p.x || typeof p.y !== 'number') return;
          var t = (typeof p.x === 'number')? p.x : Date.parse(p.x);
          if (isNaN(t) || t < monthStart || t > monthEnd) return; // only swims inside this month
          if (best === null || p.y < best) best = p.y;
        } catch(e){}
      });
      if (best !== null) vals.push({ name: name, value: best });
    });
    if (!vals.length) return; // no swimmers this month
    vals.sort(function(a,b){ return a.value - b.value });
    var fallback = false;
    var selectedIdx = N - 1; // 0-based index for 22nd
    if (vals.length <= selectedIdx){ selectedIdx = vals.length - 1; fallback = true; }
    var topN = vals.slice(0, Math.min(vals.length, N));
    out.push({ x: mstart, y: vals[selectedIdx].value, by: vals[selectedIdx].name, contributors: topN.map(function(z){ return z.name }), count: vals.length, fallback: fallback });
  });
  return out;
} 

// Compute full monthly virtual rankings (best-in-month per swimmer for each calendar month)
// Returns [{ x: mstart, label: 'Jan 2025', rankings: [ { rank:1, name:'A', value: 180.23, time:'03:00.23', date: 1600000000000 }, ... ] }]
function computeMonthlyRankings(datasets){
  var dateSet = new Set();
  datasets.forEach(function(ds){ (ds.data||[]).forEach(function(p){ if (p && p.x) dateSet.add(p.x); }); });
  var dates = Array.from(dateSet).map(function(v){ return (typeof v==='number')? v : Date.parse(v); }).filter(function(v){ return !isNaN(v); });
  if (!dates.length) return [];
  dates.sort(function(a,b){ return a - b; });
  var first = new Date(dates[0]); var last = new Date(dates[dates.length-1]);
  var months = []; var cur = Date.UTC(first.getUTCFullYear(), first.getUTCMonth(), 1); var lastMonth = Date.UTC(last.getUTCFullYear(), last.getUTCMonth(), 1);
  while (cur <= lastMonth){ months.push(cur); cur = Date.UTC(new Date(cur).getUTCFullYear(), new Date(cur).getUTCMonth()+1, 1); }

  var out = [];
  months.forEach(function(mstart){
    var monthStart = mstart;
    var monthEnd = Date.UTC(new Date(mstart).getUTCFullYear(), new Date(mstart).getUTCMonth()+1, 1) - 1; // month end
    var vals = [];
    datasets.forEach(function(ds){
      var name = (ds.label || 'Unknown'); var best = null; var bestDate = null;
      (ds.data||[]).forEach(function(p){
        try {
          if (!p || !p.x || typeof p.y !== 'number') return;
          var t = (typeof p.x === 'number')? p.x : Date.parse(p.x);
          if (isNaN(t) || t < monthStart || t > monthEnd) return; // restrict to swims within the month
          if (best === null || p.y < best) { best = p.y; bestDate = t; }
        } catch(e){}
      });
      vals.push({ name: name, value: best, date: bestDate });
    });
    // sort: swimmers with a value come first by ascending time, then swimmers with no value
    vals.sort(function(a,b){ if (a.value === null && b.value === null) return a.name.localeCompare(b.name); if (a.value === null) return 1; if (b.value === null) return -1; return a.value - b.value });
    var ranked = []; var r = 0; for (var i=0;i<vals.length;i++){ var item = vals[i]; if (item.value !== null) { r++; ranked.push({ rank: r, name: item.name, value: item.value, time: secondsToTime(item.value), date: item.date }); } else { ranked.push({ rank: null, name: item.name, value: null, time: '-', date: null }); } }
    out.push({ x: mstart, label: new Date(mstart).toLocaleDateString(undefined, { month:'short', year:'numeric' }), rankings: ranked });
  });
  return out;
}

function renderMonthlyRankings(monthly){
  try{
    var container = document.getElementById('monthly-rankings'); if (!container) return;
    if (!monthly || !monthly.length){ container.innerHTML = '<div class="small">No monthly rankings available.</div>'; return }
    var html = '';
    monthly.forEach(function(m){
      html += '<div class="rank-month">';
      html += '<div style="font-weight:bold;color:#FFD166">' + m.label + '</div>';
      html += '<table class="rank-table"><thead><tr><th style="width:60px">Rank</th><th>Swimmer</th><th style="width:110px">Best</th><th style="width:120px">Date</th></tr></thead><tbody>';
      m.rankings.forEach(function(r){
        var dateStr = r.date ? new Date(r.date).toLocaleDateString(undefined, { day:'2-digit', month:'short', year:'numeric' }) : '';
        var isUsed = (r.value !== null);
        var timeCls = (isUsed ? 'time-used ' : '') + (r.rank && r.rank <= 3 ? 'rank-fast' : (r.value ? '' : 'rank-slow'));
        var nameDisplay = r.name;
        var rowClass = '';
        if (r.name && r.name.toLowerCase().indexOf('kieran') !== -1) { nameDisplay = '<strong style="color:#FFD166">' + r.name + ' <span style="color:#bbb;font-weight:normal">(you)</span></strong>'; rowClass = 'kieran-row'; }
        html += '<tr class="' + rowClass + '"><td>' + (r.rank? r.rank : '&ndash;') + '</td><td>' + nameDisplay + '</td><td class="' + timeCls + '">' + (r.time || '-') + '</td><td>' + dateStr + '</td></tr>';
      });
      html += '</tbody></table></div>';
    });
    container.innerHTML = html;
  }catch(e){ console.warn('renderMonthlyRankings failed', e); }
}

function initQualChart(){
  if (typeof Chart === 'undefined') { debugMessages.push('Chart.js not loaded; cannot render qualifying chart'); showDebugBanner(debugMessages); return }
  // determine x range from available swim dates (we no longer require Top-22 threshold existence)
  var allX = [];
  datasets.forEach(function(d){ (d.data||[]).forEach(function(p){ if (p && p.x) allX.push(p.x); }); });
  if (!allX.length){ console.log('No swim dates available to render qualifying chart'); return }
  var minX = Math.min.apply(null, allX);
  var maxX = Math.max.apply(null, allX);

  var q2025Sec = (2*60) + 54.70; // 2:54.70 -> seconds
  var qualDatasets = [
    { label: '2025 Qualifying (2:54.70)', data: [ {x: minX, y: q2025Sec}, {x: maxX, y: q2025Sec}], borderColor:'#FFD166', borderDash:[6,4], pointRadius:0, borderWidth:2, fill:false }
  ];

  // Add monthly virtual ranking (slowest of top 22 each month) optionally when toggle is set
  try {
    var monthlyPoints = computeTop22MonthlyThresholds(datasets);
    var monthToggle = document.getElementById('show-monthly');
    if (monthlyPoints && monthlyPoints.length){
      console.log('computeTop22MonthlyThresholds: points=%d', monthlyPoints.length);
      var fallbackCount = monthlyPoints.filter(function(p){ return p.fallback; }).length;
      try { var noteEl = document.getElementById('qual-month-note'); if (noteEl) { noteEl.innerText = '(' + monthlyPoints.length + ' months' + (fallbackCount? (', '+fallbackCount+' fallback months') : '') + ')'; } } catch(e){}
      if (monthToggle) { monthToggle.disabled = false; }
      if (monthToggle && monthToggle.checked) {
        var labelText = 'Monthly 22nd (month-only, fallback=Mth)';
        qualDatasets.push({ label: labelText, data: monthlyPoints, borderColor: '#8BE38B', borderDash:[4,4], pointRadius:2, borderWidth:2, fill:false, tension:0.12 });
      }
    } else {
      try { var noteEl2 = document.getElementById('qual-month-note'); if (noteEl2) { noteEl2.innerText = '(no monthly series)'; } } catch(e){}
      if (monthToggle) { monthToggle.disabled = true; monthToggle.checked = false; }
    } 
  } catch(e){ console.warn('computeTop22MonthlyThresholds failed', e); try { var noteEl3 = document.getElementById('qual-month-note'); if (noteEl3) { noteEl3.innerText = '(monthly computation failed)'; } } catch(e){} }

  // Optionally overlay Kieran's times when the toggle is checked
  try {
    var overlayEl = document.getElementById('overlay-kieran');
    if (overlayEl && overlayEl.checked) {
      var kDataset = datasets.find(function(dd){ return dd && dd.label && dd.label.toLowerCase().indexOf('kieran') !== -1 });
      if (kDataset && kDataset.data && kDataset.data.length) {
        qualDatasets.push({ label: (kDataset.label || 'Kieran') + ' (times)', data: kDataset.data, borderColor: '#66D3FF', backgroundColor: '#66D3FF', borderWidth: 2, pointRadius: 3, fill:false, tension:0 });
        console.log('Qual chart: overlaying Kieran dataset (points=%d)', kDataset.data.length);
      } else { console.log('Qual chart: overlay requested but Kieran dataset not found'); }
    }
  } catch(e) { console.warn('overlay-kieran handler failed', e) }

  var ctxq = document.getElementById('qual-chart').getContext('2d');
  // destroy previous if exists
  if (window.qualChart && typeof window.qualChart.destroy === 'function') { window.qualChart.destroy(); }

  // Log diagnostic info about the threshold computation so it's easy to trace in console/debug files
  console.log('Qual chart x-range: min=%s, max=%s', new Date(minX).toISOString().slice(0,10), new Date(maxX).toISOString().slice(0,10));

  window.qualChart = new Chart(ctxq, {
    type: 'line',
    data: { datasets: qualDatasets },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      plugins: { 
        legend: { display: true },
        tooltip: { callbacks: {
          title: function(items){ if (items && items.length) return new Date(items[0].parsed.x).toLocaleDateString(undefined, {day:'2-digit', month:'short', year:'numeric'}); return ''; },
          label: function(item){
            var base = item.dataset.label + ': ' + secondsToTime(item.parsed.y);
            try {
              if (item && item.raw && item.raw.by){
                base += '\n (22nd: ' + item.raw.by + (item.raw.count? (', contributors: '+item.raw.count) : '') + (item.raw.fallback? ', fallback' : '') + ')';
              }
            } catch(e){}
            return base;
          }
        } }
      },
      scales: {
        x: { type: 'linear', title: { display: true, text: 'Date' }, ticks: { color: '#ddd', callback: function(v){ try{ return new Date(v).toLocaleDateString(undefined, { month: 'short', year: 'numeric' }); }catch(e){ return '' } } } },
        y: { title: { display: true, text: 'Time (mm:ss.00)' }, ticks: { color: '#ddd', callback: function(value){ return secondsToTime(value) } } }
      },
      interaction: { mode: 'nearest', intersect: false }
    }
  });

  // wire the overlay checkbox to re-render the qualifying chart when toggled (keeps behaviour simple)
  try { var ov = document.getElementById('overlay-kieran'); if (ov) { ov.removeEventListener('change', initQualChart); ov.addEventListener('change', function(){ try{ initQualChart(); } catch(e){ console.error('re-initQualChart failed', e) } }); } } catch(e) { console.warn('failed to install overlay-kieran change handler', e) }
  // wire the monthly toggle to re-render the qualifying chart
  try { var mv = document.getElementById('show-monthly'); if (mv) { mv.removeEventListener('change', initQualChart); mv.addEventListener('change', function(){ try{ initQualChart(); } catch(e){ console.error('re-initQualChart failed', e) } }); } } catch(e) { console.warn('failed to install show-monthly change handler', e) }
}
</script>
</body>
</html>
"@

# write debug fragment for offline inspection
$chartHtml = $outHtml
$chartHtml | Set-Content -Path $debugFragmentPath -Encoding UTF8
Write-Host "Wrote debug chart fragment to $debugFragmentPath"

# Write final page
$outPath = Join-Path $root 'Top_50_Swimmers_200m_Breaststroke_Chart.html'
$chartHtml | Set-Content -Path $outPath -Encoding UTF8
Write-Host "Wrote chart page to $outPath"

# Save debug_allSwimmerData.json in src for inspection
$allPath = Join-Path $root 'debug_allSwimmerData.json'
$swimmers | ConvertTo-Json -Depth 10 | Set-Content -Path $allPath -Encoding UTF8
Write-Host "Wrote debug all-swimmer data to $allPath"