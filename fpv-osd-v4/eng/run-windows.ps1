$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
try {
    if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
        throw '.NET SDK is not installed. Install .NET 10 SDK x64 first.'
    }
    $sdks = dotnet --list-sdks
    if (-not ($sdks -match '^10\.')) {
        throw '.NET 10 SDK was not found. Install .NET 10 SDK x64.'
    }

    & (Join-Path $PSScriptRoot 'check-env.ps1')
    & (Join-Path $PSScriptRoot 'build.ps1')

    $exe = Join-Path $Root 'dist/win-x64/FPV-OSD-v4.exe'
    Write-Host "`nStarting FPV OSD v4..." -ForegroundColor Green
    Start-Process -FilePath $exe
    Write-Host 'The test UI should open in a separate window.' -ForegroundColor Green
}
catch {
    Write-Host "`nFAILED: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host 'Send the full error text or a screenshot back to ChatGPT.' -ForegroundColor Yellow
    throw
}
