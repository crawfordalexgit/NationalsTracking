# Smoke tests: verify monthly rankings are month-only
# Exits with non-zero on failure
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
# Find the generated chart HTML (prefer Top_50, fall back to Top_22)
$p1 = Join-Path $root '..\src\Top_50_Swimmers_200m_Breaststroke_Chart.html'
$p2 = Join-Path $root '..\src\Top_22_Swimmers_200m_Breaststroke_Chart.html'
$paths = @($p1, $p2)
$out = $paths | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $out) { Write-Error "Could not find generated chart HTML at expected paths: $($paths -join ', ')"; exit 2 }
Write-Host "Using chart HTML: $out"
$content = Get-Content $out -Raw
# extract base64 datasets
if ($content -notmatch "var datasetsBase64\s*=\s*'([^']+)';") { Write-Error 'datasetsBase64 not found in HTML'; exit 3 }
$b64 = $Matches[1]
$json = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($b64))
$datasets = $null
try {
    if ($PSVersionTable.PSVersion -and $PSVersionTable.PSVersion.Major -ge 6) {
        $datasets = $json | ConvertFrom-Json -Depth 10
    } else {
        $datasets = $json | ConvertFrom-Json
    }
} catch { Write-Error "Failed to parse datasets JSON: $_"; exit 4 }
# normalize points to [ { label, data:[ { x: DateTime, y: number } ] } ]
$allDates = @()
foreach ($ds in $datasets) {
    $norm = @()
    foreach ($p in ($ds.data)) {
        $x = $p.x
        $dt = $null
        if ($x -is [string]) {
            try { $dt = [datetime]::Parse($x) } catch { $dt = $null }
        } elseif ($x -is [int] -or $x -is [long] -or $x -is [double]) {
            $epoch = [datetime]::UtcNow; $epoch = [datetime]::new(1970,1,1,0,0,0,[System.DateTimeKind]::Utc)
            $dt = $epoch.AddMilliseconds([double]$x)
        }
        if ($dt -ne $null -and ($p.y -ne $null)) { $norm += [PSCustomObject]@{ x = $dt; y = [double]$p.y; raw=$p } ; $allDates += $dt }
    }
    $ds.PSObject.Properties.Remove('data')
    $ds | Add-Member -NotePropertyName data -NotePropertyValue $norm -Force
}
if (-not $allDates) { Write-Error 'No valid swim dates/points found in datasets'; exit 5 }
# compute month range
$earliest = ($allDates | Sort-Object)[0]
$latest = ($allDates | Sort-Object)[-1]
$months = @()
$cur = [datetime]::new($earliest.Year, $earliest.Month, 1)
while ($cur -le [datetime]::new($latest.Year, $latest.Month, 1)) {
    $months += $cur
    if ($cur.Month -eq 12) { $cur = [datetime]::new($cur.Year+1, 1, 1) } else { $cur = [datetime]::new($cur.Year, $cur.Month+1, 1) }
}
$errors = @()
foreach ($m in $months) {
    $mStart = $m
    $mEnd = if ($m.Month -eq 12) { [datetime]::new($m.Year+1,1,1).AddMilliseconds(-1) } else { [datetime]::new($m.Year, $m.Month+1, 1).AddMilliseconds(-1) }
    foreach ($ds in $datasets) {
        $best = $null; $bestDate = $null
        foreach ($p in $ds.data) {
            if ($p.x -ge $mStart -and $p.x -le $mEnd) {
                if ($best -eq $null -or $p.y -lt $best) { $best = $p.y; $bestDate = $p.x }
            }
        }
        if ($best -ne $null) {
            if ($bestDate.Month -ne $mStart.Month -or $bestDate.Year -ne $mStart.Year) {
                $errors += [PSCustomObject]@{ month = $mStart.ToString('yyyy-MM'); swimmer = $ds.label; best = $best; bestDate = $bestDate.ToString('yyyy-MM-dd') }
            }
        }
    }
}
if ($errors.Count -gt 0) {
    Write-Error "Monthly smoke test FAILED: found $($errors.Count) best-in-month misassignments. Sample:" 
    $errors | Select-Object -First 20 | Format-Table -AutoSize
    exit 6
}
Write-Host 'Monthly smoke test PASSED: all best-in-month dates are inside their month'
exit 0
