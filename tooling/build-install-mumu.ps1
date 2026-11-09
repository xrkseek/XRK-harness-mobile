#Requires -Version 5.1
# Thin pointer → harness workspace skill script (single source of truth).
$tooling = Split-Path -Parent $MyInvocation.MyCommand.Path
$mobileRoot = Split-Path -Parent $tooling
$workspace = Split-Path -Parent $mobileRoot
$target = Join-Path $workspace 'XRK-harness\.agents\skills\xrk-mobile-apk\scripts\build-install-mumu.ps1'
if (-not (Test-Path -LiteralPath $target)) {
  Write-Host "build-install-mumu: missing $target" -ForegroundColor Red
  exit 1
}
& $target @args
exit $LASTEXITCODE
