$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Desktop = Join-Path $Root 'src/FpvOsd.Desktop/FpvOsd.Desktop.csproj'
$Smoke = Join-Path $Root 'tests/FpvOsd.Core.Smoke/FpvOsd.Core.Smoke.csproj'

Write-Host '== FPV OSD v4 build =='
dotnet --info

dotnet restore $Desktop
dotnet build $Desktop -c Release --no-restore
dotnet run --project $Smoke -c Release

$Dist = Join-Path $Root 'dist/win-x64'
if (Test-Path $Dist) { Remove-Item -Recurse -Force $Dist }
dotnet publish $Desktop -c Release -r win-x64 --self-contained false -o $Dist

$Exe = Join-Path $Dist 'FPV-OSD-v4.exe'
if (!(Test-Path $Exe)) { throw "Expected EXE not found: $Exe" }
Get-FileHash $Exe -Algorithm SHA256 | Format-List
Write-Host "Built: $Exe"
