# Download local UMD bundles for Chart.js and chartjs-adapter-date-fns into src/vendor/
# Usage: .\scripts\vendor_chart_js.ps1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$dest = Join-Path $root '..\src\vendor'
if (-not (Test-Path $dest)) { New-Item -ItemType Directory -Path $dest | Out-Null }

$chartUrl = 'https://cdn.jsdelivr.net/npm/chart.js/dist/chart.umd.min.js'
$adapterUrl = 'https://cdn.jsdelivr.net/npm/chartjs-adapter-date-fns/dist/chartjs-adapter-date-fns.min.js'
# Also try the official bundled adapter which includes date-fns (preferred when available locally)
$adapterBundleUrl = 'https://cdn.jsdelivr.net/npm/chartjs-adapter-date-fns@3.0.0/dist/chartjs-adapter-date-fns.bundle.min.js'
# Try known candidate UMD paths for date-fns (some CDN layouts differ across versions)
$dateFnsCandidates = @(
  'https://cdn.jsdelivr.net/npm/date-fns@2.29.3/umd/date-fns.min.js',
  'https://cdn.jsdelivr.net/npm/date-fns@2.30.0/umd/date-fns.min.js',
  'https://cdn.jsdelivr.net/npm/date-fns/umd/date-fns.min.js',
  'https://unpkg.com/date-fns@2.29.3/umd/date-fns.min.js',
  'https://unpkg.com/date-fns/umd/date-fns.min.js'
)
$chartOut = Join-Path $dest 'chart.umd.min.js'
$adapterOut = Join-Path $dest 'chartjs-adapter-date-fns.min.js'
$dateFnsOut = Join-Path $dest 'date-fns.min.js'

Write-Host "Downloading Chart.js UMD -> $chartOut"
try { Invoke-WebRequest -Uri $chartUrl -OutFile $chartOut -UseBasicParsing -TimeoutSec 60 } catch { Write-Error "Failed to download Chart.js: $_"; exit 1 }

Write-Host "Downloading chartjs-adapter-date-fns -> $adapterOut"
try { Invoke-WebRequest -Uri $adapterUrl -OutFile $adapterOut -UseBasicParsing -TimeoutSec 60 } catch { Write-Warning "Failed to download adapter: $_" }

# Try to download the bundled adapter (includes date-fns) as a preferred local artifact
$adapterBundleOut = Join-Path $dest 'chartjs-adapter-date-fns.bundle.min.js'
Write-Host "Attempting to download bundled adapter -> $adapterBundleOut"
try { Invoke-WebRequest -Uri $adapterBundleUrl -OutFile $adapterBundleOut -UseBasicParsing -TimeoutSec 60; Write-Host "Downloaded bundled adapter" } catch { Write-Warning "Bundled adapter not available: $_" }

# Try date-fns candidates until one succeeds (do not fail the whole script if none are available; adapter can still work via CDN)
$downloadedDateFns = $false
foreach ($candidate in $dateFnsCandidates) {
    Write-Host "Trying date-fns candidate: $candidate"
    try {
        Invoke-WebRequest -Uri $candidate -OutFile $dateFnsOut -UseBasicParsing -TimeoutSec 30
        Write-Host "Downloaded date-fns from: $candidate -> $dateFnsOut"
        $downloadedDateFns = $true
        break
    } catch {
        Write-Warning "Candidate failed: $candidate ($_). Trying next candidate..."
    }
}

if (-not $downloadedDateFns) { Write-Warning "Warning: Could not download a local date-fns UMD build. The chart adapter may still work if CDN versions are reachable from the browser. To force a local copy, add a reachable UMD build to $dest manually." }

if ((Test-Path $chartOut) -and (Test-Path $adapterOut)) {
    if ($downloadedDateFns) { Write-Host "Vendor files saved to $dest"; exit 0 } else { Write-Warning "Vendor Chart and adapter saved to $dest; date-fns not downloaded."; exit 0 }
} else {
    Write-Error "Failed to download required vendor files (Chart.js or adapter missing)"; exit 1
}