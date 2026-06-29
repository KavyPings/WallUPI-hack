#!/usr/bin/env pwsh
# Wallupi - Start backend + ngrok tunnel
# Run from the project root:  .\start_backend.ps1

$root      = $PSScriptRoot
$backend   = Join-Path $root "backend"
$python    = "C:\Users\Kavy Khilrani\AppData\Local\Programs\Python\Python312\python.exe"
$ngrokExe  = "C:\Users\Kavy Khilrani\Downloads\ngrok-v3-stable-windows-amd64\ngrok.exe"
$domain    = "https://entrench-retaliate-agnostic.ngrok-free.dev"

Write-Host ""
Write-Host "  WALLUPI - AI Fraud Detection Backend" -ForegroundColor Cyan
Write-Host "  ----------------------------------------" -ForegroundColor DarkGray
Write-Host ""

# 1. Start Flask
Write-Host "  [1/2] Starting Flask backend on port 5000..." -ForegroundColor Yellow
$flask = Start-Process -FilePath $python `
    -ArgumentList "app.py" `
    -WorkingDirectory $backend `
    -PassThru -WindowStyle Normal
Write-Host "        PID $($flask.Id) - Flask is starting up" -ForegroundColor DarkGray
Start-Sleep -Seconds 2

# 2. Start ngrok with static domain
# Uses global ngrok config (~\AppData\Local\ngrok\ngrok.yml) for authtoken.
# The --config flag for a project file would override global auth in v3, so
# we pass the domain directly on the command line instead.
Write-Host "  [2/2] Starting ngrok tunnel..." -ForegroundColor Yellow
$ngrok = Start-Process -FilePath $ngrokExe `
    -ArgumentList "http --domain=entrench-retaliate-agnostic.ngrok-free.dev 5000" `
    -PassThru -WindowStyle Normal
Write-Host "        PID $($ngrok.Id) - ngrok is connecting" -ForegroundColor DarkGray
Start-Sleep -Seconds 3

# Verify tunnel is up
$tunnelUp = $false
for ($i = 0; $i -lt 8; $i++) {
    Start-Sleep -Seconds 1
    try {
        $r = Invoke-RestMethod -Uri "http://localhost:4040/api/tunnels" -ErrorAction Stop
        if ($r.tunnels.Count -gt 0) { $tunnelUp = $true; break }
    } catch { }
}

Write-Host ""
if ($tunnelUp) {
    Write-Host "  [OK] Everything is running!" -ForegroundColor Green
} else {
    Write-Host "  [!!] ngrok may still be connecting - check its window." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "  Public URL : $domain" -ForegroundColor White
Write-Host "  Dashboard  : http://localhost:4040" -ForegroundColor DarkGray
Write-Host "  Health     : $domain/" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  APK is already built with this URL - share it freely." -ForegroundColor Green
Write-Host "  Keep this window open while the app is in use." -ForegroundColor DarkGray
Write-Host "  Press Ctrl+C to stop Flask + ngrok." -ForegroundColor DarkGray
Write-Host ""

# Keep alive; kill children on Ctrl+C
try {
    while ($true) { Start-Sleep -Seconds 5 }
} finally {
    Write-Host ""
    Write-Host "  Shutting down..." -ForegroundColor Yellow
    if (-not $flask.HasExited) { Stop-Process -Id $flask.Id  -Force -ErrorAction SilentlyContinue }
    if (-not $ngrok.HasExited) { Stop-Process -Id $ngrok.Id  -Force -ErrorAction SilentlyContinue }
    Write-Host "  Flask and ngrok stopped. Goodbye." -ForegroundColor Cyan
    Write-Host ""
}
