$ErrorActionPreference = 'Continue'

Write-Host '=== FPV OSD v4 environment ===' -ForegroundColor Cyan

function Check-Command($Name) {
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if ($cmd) {
        Write-Host "[OK] $Name -> $($cmd.Source)" -ForegroundColor Green
        return $true
    }
    Write-Host "[MISSING] $Name" -ForegroundColor Yellow
    return $false
}

$hasDotnet = Check-Command dotnet
$hasJava = Check-Command java
$hasAdb = Check-Command adb

if ($hasDotnet) {
    Write-Host "`n.NET SDKs:"
    dotnet --list-sdks
    Write-Host "`n.NET workloads:"
    dotnet workload list
}

if ($hasJava) {
    Write-Host "`nJava:"
    java -version
}

if ($hasAdb) {
    Write-Host "`nADB:"
    adb version
    Write-Host "`nConnected Android devices:"
    adb devices
}

Write-Host "`nExpected for FPV OSD v4:" -ForegroundColor Cyan
Write-Host '  Desktop: .NET SDK 10.x'
Write-Host '  Android: .NET SDK 10.x + android workload + JDK 21 + Android SDK/platform-tools'
