# Runner to execute regen, fetch historicals, and generate chart
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Push-Location $root

Write-Host "Running regen_cache.ps1..."
& "$root\regen_cache.ps1"

Write-Host "Running Fetch-HistoricalTimes.ps1..."
& "$root\Fetch-HistoricalTimes.ps1"

Write-Host "Running Get-TopSwimmersChart.ps1..."
& "$root\..\src\Get-TopSwimmersChart.ps1"

# run monthly smoke tests to detect regressions (exit non-zero on failure)
Write-Host "Running monthly smoke tests..."
& "$root\run_smoke_tests.ps1"
if ($LASTEXITCODE -ne 0) { Write-Error "Monthly smoke tests failed (exit code $LASTEXITCODE). Aborting run."; exit $LASTEXITCODE }

# choose generated chart file to open (prefer Top_50 if present)
$outHtmlCandidates = @((Join-Path $root '..\src\Top_50_Swimmers_200m_Breaststroke_Chart.html'), (Join-Path $root '..\src\Top_22_Swimmers_200m_Breaststroke_Chart.html'))
$outHtml = $outHtmlCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($outHtml) { Write-Host "Opening generated chart page in default browser..."; Start-Process -FilePath $outHtml }

Write-Host "Smoke test complete. Debug files written to ./debug and ./src (debug_allSwimmerData.json)"
Pop-Location