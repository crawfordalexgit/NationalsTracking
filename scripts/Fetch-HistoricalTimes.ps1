# Fetch-HistoricalTimes.ps1 — fetch per-swimmer historical times from Swim England (LC + SC best-effort)
# This script reads src/swimmer_cache.json and updates each swimmer's HistoricalTimes array
# It writes failures to debug/debug_sc_failures.log and produces src/debug_allSwimmerData.json for inspection

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$src = Join-Path $scriptDir '..\src\swimmer_cache.json'
$src = [System.IO.Path]::GetFullPath($src)
$debugDir = Join-Path (Split-Path $src -Parent) '..\debug'
$debugDir = [System.IO.Path]::GetFullPath($debugDir)
if (-not (Test-Path $debugDir)) { New-Item -ItemType Directory -Path $debugDir | Out-Null }
$failureLog = Join-Path $debugDir 'debug_sc_failures.log'

if (-not (Test-Path $src)) { Write-Error "Cache not found at $src"; exit 1 }
$swimmers = Get-Content $src -Raw | ConvertFrom-Json

function TimeToSeconds($t) {
    if (-not $t) { return $null }
    $parts = $t -split ':'
    if ($parts.Count -eq 2) { return ([double]$parts[0]*60) + [double]$parts[1] }
    if ($parts.Count -eq 3) { return ([double]$parts[0]*3600) + ([double]$parts[1]*60) + [double]$parts[2] }
    return $null
}

$wc = New-Object System.Net.WebClient
$wc.Headers['User-Agent'] = 'Mozilla/5.0 (Windows NT)'
$wc.Headers['Accept'] = 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'
$wc.Encoding = [System.Text.Encoding]::UTF8

# Helper: try multiple URL variants and return HTML or $null
function TryFetchPersonalBest($tiref, $course, $overrideUrl=$null) {
    $pool = if ($course -eq 'L') { 'L' } else { 'S' }

    # If caller provided a full URL (PersonalBestUrl), try it first
    if ($overrideUrl) {
        try {
            Write-Host "  Trying swimmer PersonalBestUrl: $overrideUrl"
            $hdrs = @{ 'User-Agent' = 'Mozilla/5.0 (Windows NT)'; 'Accept' = 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'; 'Accept-Language' = 'en-GB,en;q=0.9'; 'Referer' = 'https://www.swimmingresults.org/12months/last12.php' }
            try {
                $resp = Invoke-WebRequest -Uri $overrideUrl -Headers $hdrs -UseBasicParsing -ErrorAction Stop -TimeoutSec 30
                $html = $resp.Content
                if ($html) { return $html }
            } catch {
                try { $html = $wc.DownloadString($overrideUrl); if ($html) { return $html } } catch { $_ | Out-String | Out-File -FilePath $failureLog -Append }
            }
        } catch {
            $_ | Out-String | Out-File -FilePath $failureLog -Append
        }
    }

    $variants = @(
        "/individualbest/personal_best_time_date.php?tiref=$tiref&mode=$course&tstroke=9&tcourse=$course",
        "/individualbest/personal_best_time_date.php?back=12months&Pool=$pool&Stroke=9&Sex=M&AgeGroup=13&date-1-dd=31&date-1-mm=12&date-1=2026&StartNumber=1&RecordsToView=50&Level=N&TargetClub=XXXX&TargetRegion=P&TargetCounty=XXXX&TargetNationality=E&tiref=$tiref&mode=$course&tstroke=9&tcourse=$course",
        "/individualbest/personal_best.php?tiref=$tiref&mode=$course&tstroke=9&tcourse=$course",
        "/personal_best_time_date.php?tiref=$tiref&mode=$course&tstroke=9&tcourse=$course",
        "/personal_best.php?tiref=$tiref&mode=$course&tstroke=9&tcourse=$course",
        "/personal_best_time_date.php?back=12months&Pool=$pool&Stroke=9&Sex=M&AgeGroup=13&date-1-dd=31&date-1-mm=12&date-1=2026&StartNumber=1&RecordsToView=50&Level=N&TargetClub=XXXX&TargetRegion=P&TargetCounty=XXXX&TargetNationality=E&tiref=$tiref&mode=$course&tstroke=9&tcourse=$course"
    )
    foreach ($v in $variants) {
        $url = 'https://www.swimmingresults.org' + $v
        try {
            # prefer Invoke-WebRequest for more realistic headers and cookies
            $hdrs = @{ 'User-Agent' = 'Mozilla/5.0 (Windows NT)'; 'Accept' = 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'; 'Accept-Language' = 'en-GB,en;q=0.9'; 'Referer' = 'https://www.swimmingresults.org/12months/last12.php' }
            try {
                Write-Host "  Trying URL: $url"
                $resp = Invoke-WebRequest -Uri $url -Headers $hdrs -UseBasicParsing -ErrorAction Stop -TimeoutSec 30
                $html = $resp.Content
                if ($html) { return $html }
            } catch {
                # fallback to WebClient
                try { $html = $wc.DownloadString($url); if ($html) { return $html } } catch { $_ | Out-String | Out-File -FilePath $failureLog -Append }
            }
        } catch {
            $_ | Out-String | Out-File -FilePath $failureLog -Append
            Start-Sleep -Milliseconds 500
        }
    }
    return $null
}

# Parse HTML table rows of times into objects
function ParsePersonalBestHtml($html, $course) {
    $list = @()
    if (-not $html) { return $list }

    # find table rows
    $rows = [regex]::Matches($html, '<tr[^>]*>(.*?)</tr>', 'Singleline')
    foreach ($r in $rows) {
        $cells = [regex]::Matches($r.Groups[1].Value, '<t[dh][^>]*>(.*?)</t[dh]>', 'Singleline')
        if ($cells.Count -ge 1) {
            # Collect cleaned cell texts
            $texts = @()
            foreach ($c in $cells) { $texts += ($c.Groups[1].Value -replace '<[^>]+>','').Trim() }

            # Find time (e.g. 3:01.11 or 3:01) and date (e.g. 27/04/25)
            $timeText = $texts | Where-Object { $_ -match '\d{1,2}:\d{2}(?:\.\d+)?' } | Select-Object -First 1
            $dateText = $texts | Where-Object { $_ -match '\d{1,2}/\d{1,2}/\d{2,4}' } | Select-Object -First 1

            if ($timeText -and $dateText) {
                try { $date = [datetime]::Parse($dateText) } catch { $date = (Get-Date).Date }
                $courseName = if ($course -eq 'L') { 'LC' } else { 'SC' }
                # pick a sensible Meet description (first non-empty cell that's not date/time)
                $meet = ($texts | Where-Object { ($_ -ne $timeText) -and ($_ -ne $dateText) -and ($_ -ne '') } | Select-Object -First 1)
                $entry = [PSCustomObject]@{
                    Date = $date.ToString('yyyy-MM-dd')
                    Course = $courseName
                    Time = $timeText
                    Seconds = TimeToSeconds($timeText)
                    Meet = $meet
                }
                $list += $entry
            }
        }
    }

    # Deduplicate rows (some pages include both "Swims in Time Order" and "Swims in Date Order")
    if ($list.Count -gt 1) {
        $list = $list | Group-Object -Property { $_.Date + '|' + $_.Time } | ForEach-Object { $_.Group[0] }
    }

    return $list
}

$swCount = 0
$fetchFailures = @()
foreach ($s in $swimmers) {
    $swCount++
    Write-Host "Fetching history for $($s.Name) (tiref=$($s.Tiref))"
    $hist = @()
    # Only fetch Long Course for this page
    foreach ($course in @('L')) {
        $overrideUrl = $s.PersonalBestUrl
        if ($overrideUrl) { Write-Host "  Using PersonalBestUrl for fetch: $overrideUrl" }
        $html = TryFetchPersonalBest $s.Tiref $course $overrideUrl
        if ($html) {
            $parsed = ParsePersonalBestHtml $html $course
            if ($parsed.Count -gt 0) { $hist += $parsed }
        } else {
            $fetchFailures += "Failed: $($s.Name) $course"
        }
        Start-Sleep -Milliseconds 600
    }
    # Keep only LC entries and sort
    $hist = $hist | Where-Object { $_.Course -eq 'LC' }
    if ($hist.Count -gt 0) {
        $hist = $hist | Sort-Object @{Expression = { [datetime]$_.Date }}
        $s.HistoricalTimes = $hist
    } else {
        # fallback to single LcTime entry
        if ($s.LcTime) {
            $entry = [PSCustomObject]@{
                Date = (Get-Date).ToString('yyyy-MM-dd')
                Course = 'LC'
                Time = $s.LcTime
                Seconds = TimeToSeconds($s.LcTime)
                Meet = 'derived'
            }
            $s.HistoricalTimes = @($entry)
        }
    }
    # Add a historical count for debugging and write to console
    $count = 0
    if ($s.HistoricalTimes) { $count = ($s.HistoricalTimes | Where-Object { $_.Course -eq 'LC' }).Count }
    $s | Add-Member -NotePropertyName HistoricalCount -NotePropertyValue $count -Force
    Write-Host (" => Found {0} LC swims for {1} (tiref={2})" -f $count, $s.Name, $s.Tiref) -ForegroundColor Green
}

# Log failures
$fetchFailures | Out-File -FilePath $failureLog -Encoding UTF8
Write-Host "Fetch completed for $swCount swimmers. Failures written to $failureLog"

# Persist back to cache and write debug_allSwimmerData.json
$swimmers | ConvertTo-Json -Depth 10 | Set-Content -Path $src -Encoding UTF8
$dst = Join-Path (Split-Path $src -Parent) 'debug_allSwimmerData.json'
$swimmers | ConvertTo-Json -Depth 10 | Set-Content -Path $dst -Encoding UTF8
Write-Host "Wrote debug all-swimmer data to $dst"

# Also write a small historical-counts summary for quick inspection
$summary = $swimmers | ForEach-Object { [PSCustomObject]@{ Name = $_.Name; Tiref = $_.Tiref; HistoricalCount = ($_.HistoricalTimes | Where-Object { $_.Course -eq 'LC' } | Measure-Object).Count } }
$summaryPath = Join-Path $debugDir 'historical_counts.json'
$summary | ConvertTo-Json -Depth 4 | Set-Content -Path $summaryPath -Encoding UTF8
Write-Host "Wrote historical counts to $summaryPath"
