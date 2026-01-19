<#
Simple local server helper for development.
Usage: .\scripts\serve.ps1 [-Port 8000]
It will try to use python if available (python -m http.server), otherwise falls back to a tiny PowerShell HttpListener.
#>
param(
  [int]$Port = 8000
)

# Helper to find repo root (this script lives in ./scripts)
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$siteDir = Join-Path $root '..\src' | Resolve-Path -ErrorAction SilentlyContinue
if (-not $siteDir) { Write-Error "Could not find ./src directory relative to script. Run this from the repo root."; exit 1 }
$siteDir = $siteDir.ProviderPath

# Try python simple server first (most users have python installed)
if (Get-Command python -ErrorAction SilentlyContinue) {
  Write-Host "Starting Python HTTP server to serve: $siteDir (http://localhost:$Port)" -ForegroundColor Green
  Push-Location $siteDir
  $proc = Start-Process -FilePath python -ArgumentList "-m","http.server","$Port" -NoNewWindow -PassThru
  Write-Host "Python server started (PID: $($proc.Id)). Press Ctrl+C or run Stop-Process -Id $($proc.Id) to stop." -ForegroundColor Yellow
  Wait-Process -Id $proc.Id
  Pop-Location
  exit 0
}

# Fallback: lightweight HttpListener
Add-Type -AssemblyName System.Net.HttpListener
$listener = New-Object System.Net.HttpListener
$prefix = "http://+:$Port/"
$listener.Prefixes.Add($prefix)
try {
  $listener.Start()
} catch {
  Write-Error "Failed to start listener on $prefix: $_"; exit 1
}
Write-Host "Serving $siteDir on http://localhost:$Port (Press Ctrl+C to quit)" -ForegroundColor Green

while ($listener.IsListening) {
  $context = $listener.GetContext()
  Start-Job -ArgumentList $context, $siteDir -ScriptBlock {
    param($ct, $rootDir)
    try {
      $req = $ct.Request
      $res = $ct.Response
      $path = $req.Url.AbsolutePath.TrimStart('/')
      if ([string]::IsNullOrEmpty($path)) { $path = 'Top_50_Swimmers_200m_Breaststroke_Chart.html' }
      $file = Join-Path $rootDir $path
      if (-not (Test-Path $file)) {
        # try index.html in directory
        if (Test-Path (Join-Path $rootDir $path 'index.html')) { $file = Join-Path $rootDir $path 'index.html' }
      }
      if (-not (Test-Path $file)) {
        $res.StatusCode = 404
        $buffer = [System.Text.Encoding]::UTF8.GetBytes("Not Found: $path")
        $res.ContentType = 'text/plain'
        $res.OutputStream.Write($buffer, 0, $buffer.Length)
        $res.Close()
        return
      }
      $ext = [System.IO.Path]::GetExtension($file).ToLowerInvariant()
      $mime = switch ($ext) {
        '.html' { 'text/html' }
        '.js'   { 'application/javascript' }
        '.json' { 'application/json' }
        '.css'  { 'text/css' }
        '.png'  { 'image/png' }
        '.jpg'  { 'image/jpeg' }
        '.svg'  { 'image/svg+xml' }
        default { 'application/octet-stream' }
      }
      $res.ContentType = $mime
      $bytes = [System.IO.File]::ReadAllBytes($file)
      $res.ContentLength64 = $bytes.Length
      $res.OutputStream.Write($bytes, 0, $bytes.Length)
      $res.Close()
    } catch {
      try { $ct.Response.StatusCode = 500; $ct.Response.Close() } catch {}
    }
  } | Out-Null
}
