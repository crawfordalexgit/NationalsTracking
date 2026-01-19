# regen_cache.ps1 — create a sample swimmer_cache.json with top-22 sample data
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$dstDir = Join-Path $scriptDir '..\src'
$dstDir = [System.IO.Path]::GetFullPath($dstDir)
if (-not (Test-Path $dstDir)) { New-Item -Path $dstDir -ItemType Directory -Force | Out-Null }
$dst = Join-Path $dstDir 'swimmer_cache.json'

$TopN = 50 # number of top-ranked swimmers to fetch

$swimmers = @()

# Try to fetch the top N from the rankings page; ordered extraction ensures we get the true top N
try {
    $rankingsUrl = 'https://www.swimmingresults.org/12months/last12.php?Pool=L&Stroke=9&Sex=M&AgeGroup=13&date=31%2F12%2F2026&StartNumber=1&RecordsToView=100&Level=N&TargetNationality=E&TargetRegion=P&TargetCounty=XXXX&TargetClub=XXXX'
    Write-Host "Downloading rankings page to collect top $TopN names..."
    $hdrs = @{ 'User-Agent' = 'Mozilla/5.0 (Windows NT)'; 'Accept' = 'text/html' }
    $resp = Invoke-WebRequest -Uri $rankingsUrl -Headers $hdrs -UseBasicParsing -ErrorAction Stop -TimeoutSec 30
    $html = $resp.Content

    # pattern to capture anchor order and tiref
    $pattern = '(?si)<a[^>]*tiref=(\d+)[^>]*>([^<]+)</a>'
    $matches = [regex]::Matches($html, $pattern)

    $seen = @{}
    $count = 0
    foreach ($m in $matches) {
        if ($count -ge $TopN) { break }
        $tid = [int]$m.Groups[1].Value
        $name = ($m.Groups[2].Value).Trim() -replace '\s+', ' '
        $key = $name.ToLower()
        if (-not [string]::IsNullOrWhiteSpace($name) -and -not $seen.ContainsKey($key)) {
            $sw = [PSCustomObject]@{ Name = $name; Tiref = $tid; Club = $null; YOB = 2013; LcTime = $null; HistoricalTimes = @() }
            $swimmers += $sw
            $seen[$key] = $true
            $count++
            Write-Host ("Found ranking #{0}: {1} (tiref={2})" -f $count, $name, $tid)
        }
    }
    Write-Host "Collected $($swimmers.Count) swimmers from rankings page"
} catch {
    Write-Warning "Could not fetch rankings page to build top-$TopN list: $_" 
}

# Fallback: if we couldn't collect enough names, populate with a small built-in sample list
if ($swimmers.Count -lt $TopN) {
    Write-Warning "Only $($swimmers.Count) swimmers collected; filling remaining with sample names to reach $TopN"
    $sample = @(
        'Oliver Laszlo','Lucas Yu','Arthur Foran','Dewi Fordyce','Evan Lau','Luke Wallace','Sam Clarke','Aleksander Palka','Bran Acuavera','Rahul Reedha',
        'Zachary Cornwell','Noeh Smith','Edward Shepherd','Boris Kaloyanov','Daniel Ma','George Swales','Raditya Bimantara','Jude Andrews-Kumah','Aiden Doorbeejan','Ethan Craven',
        'Kevin Varga','Harrison Han','Kieran Crawford','Extra Sample1','Extra Sample2','Extra Sample3','Extra Sample4','Extra Sample5','Extra Sample6','Extra Sample7',
        'Extra Sample8','Extra Sample9','Extra Sample10','Extra Sample11','Extra Sample12','Extra Sample13','Extra Sample14','Extra Sample15','Extra Sample16','Extra Sample17',
        'Extra Sample18','Extra Sample19','Extra Sample20','Extra Sample21','Extra Sample22','Extra Sample23','Extra Sample24','Extra Sample25','Extra Sample26','Extra Sample27'
    )
    foreach ($name in $sample) {
        if ($swimmers.Count -ge $TopN) { break }
        if (-not ($swimmers | Where-Object { $_.Name -eq $name })) {
            $swimmers += [PSCustomObject]@{ Name = $name; Tiref = $null; Club = $null; YOB = 2013; LcTime = $null; HistoricalTimes = @() }
        }
    }
    Write-Host "Now have $($swimmers.Count) swimmers in cache (including samples)"
}

# Construct per-swimmer PersonalBestUrl for 200m LC breaststroke using the mapped tiref where available
$template = 'https://www.swimmingresults.org/individualbest/personal_best_time_date.php?back=12months&Pool=L&Stroke=9&Sex=M&AgeGroup=13&date-1-dd=31&date-1-mm=12&date-1=2026&StartNumber=1&RecordsToView=100&Level=N&TargetClub=XXXX&TargetRegion=P&TargetCounty=XXXX&TargetNationality=E&tiref={0}&mode=L&tstroke=9&tcourse=L'
foreach ($s in $swimmers) {
    if ($s.Tiref -and $s.Tiref -ne 0) {
        $s | Add-Member -NotePropertyName PersonalBestUrl -NotePropertyValue ([string]::Format($template, $s.Tiref)) -Force
        Write-Host "Set PersonalBestUrl for $($s.Name) -> $($s.PersonalBestUrl)"
    } else {
        $s | Add-Member -NotePropertyName PersonalBestUrl -NotePropertyValue $null -Force
        Write-Warning "No tiref for $($s.Name); PersonalBestUrl left null"
    }
}

# write out cache
$swimmers | ConvertTo-Json -Depth 10 | Set-Content -Path $dst -Encoding UTF8
Write-Host "Wrote swimmer cache ($($swimmers.Count) swimmers) to $dst"