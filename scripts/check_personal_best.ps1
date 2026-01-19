param([string]$Url)

$hdrs = @{ 'User-Agent' = 'Mozilla/5.0 (Windows NT)'; 'Accept' = 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8' }
try {
    $resp = Invoke-WebRequest -Uri $Url -Headers $hdrs -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop
    $html = $resp.Content
} catch {
    $wc = New-Object System.Net.WebClient
    $wc.Headers['User-Agent'] = 'Mozilla/5.0 (Windows NT)'
    $html = $wc.DownloadString($Url)
}

# Save raw HTML for inspection
if ($Url -match 'tiref=(\d+)') { $t = $matches[1] } else { $t = 'unknown' }
$debugDir = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) '..\debug'
if (-not (Test-Path $debugDir)) { New-Item -ItemType Directory -Path $debugDir | Out-Null }
$debugFile = Join-Path $debugDir ("hb_$t.html")
Set-Content -Path $debugFile -Value $html -Encoding UTF8
Write-Host "Saved raw page to $debugFile"

$rows = [regex]::Matches($html, '<tr[^>]*>(.*?)</tr>', 'Singleline')
$list = @()
foreach ($r in $rows) {
    $cells = [regex]::Matches($r.Groups[1].Value, '<t[dh][^>]*>(.*?)</t[dh]>', 'Singleline')
    if ($cells.Count -ge 1) {
        $texts = @()
        foreach ($c in $cells) { $texts += ($c.Groups[1].Value -replace '<[^>]+>', '').Trim() }
        $timeText = $texts | Where-Object { $_ -match '\d{1,2}:\d{2}(?:\.\d+)?' } | Select-Object -First 1
        $dateText = $texts | Where-Object { $_ -match '\d{1,2}/\d{1,2}/\d{2,4}' } | Select-Object -First 1
        if ($timeText -and $dateText) {
            try { $d = [datetime]::Parse($dateText) } catch { $d = (Get-Date).Date }
            $meet = ($texts | Where-Object { ($_ -ne $timeText) -and ($_ -ne $dateText) -and ($_ -ne '') } | Select-Object -First 1)
            $entry = [PSCustomObject]@{
                Date = $d.ToString('yyyy-MM-dd')
                Time = $timeText
                Meet = $meet
            }
            $list += $entry
        }
    }
}

# Deduplicate repeated tables (time/date order duplicates)
if ($list.Count -gt 1) { $list = $list | Group-Object -Property { $_.Date + '|' + $_.Time } | ForEach-Object { $_.Group[0] } }

$list | Select-Object Date,Time,Meet | Format-Table -AutoSize
Write-Host ''
Write-Host ('Found {0} LC swims on this page' -f $list.Count)
