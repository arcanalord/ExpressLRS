param(
    [string]$OutputZip = "$PWD\fpv-osd-v4-nuget-offline.zip"
)

$ErrorActionPreference = 'Stop'

function Require-Command([string]$Name) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command not found: $Name"
    }
}

Require-Command dotnet

$work = Join-Path $env:TEMP ("fpv-osd-v4-nuget-" + [guid]::NewGuid().ToString('N'))
$projectDir = Join-Path $work 'probe'
$feedDir = Join-Path $work 'offline-feed'
New-Item -ItemType Directory -Force -Path $projectDir, $feedDir | Out-Null

$project = @'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net10.0</TargetFramework>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="Avalonia" Version="12.1.2" />
    <PackageReference Include="Avalonia.Desktop" Version="12.1.2" />
    <PackageReference Include="Avalonia.Themes.Fluent" Version="12.1.2" />
    <PackageReference Include="Avalonia.Fonts.Inter" Version="12.1.2" />
  </ItemGroup>
</Project>
'@

$projectPath = Join-Path $projectDir 'OfflineProbe.csproj'
Set-Content -Path $projectPath -Value $project -Encoding UTF8

Write-Host 'Restoring Avalonia dependencies for linux-x64...' -ForegroundColor Cyan
dotnet restore $projectPath -r linux-x64 --force --no-cache
if ($LASTEXITCODE -ne 0) { throw "dotnet restore failed: $LASTEXITCODE" }

$assetsPath = Join-Path $projectDir 'obj\project.assets.json'
if (-not (Test-Path $assetsPath)) { throw "project.assets.json not found: $assetsPath" }

$assets = Get-Content $assetsPath -Raw | ConvertFrom-Json
$packages = @()
foreach ($prop in $assets.libraries.PSObject.Properties) {
    $lib = $prop.Value
    if ($lib.type -eq 'package') {
        $parts = $prop.Name -split '/', 2
        if ($parts.Count -eq 2) {
            $packages += [pscustomobject]@{ Id = $parts[0]; Version = $parts[1] }
        }
    }
}
$packages = $packages | Sort-Object Id, Version -Unique

Write-Host ("Resolved {0} NuGet packages." -f $packages.Count) -ForegroundColor Green

$manifest = @()
foreach ($pkg in $packages) {
    $idLower = $pkg.Id.ToLowerInvariant()
    $versionLower = $pkg.Version.ToLowerInvariant()
    $fileName = "$idLower.$versionLower.nupkg"
    $url = "https://api.nuget.org/v3-flatcontainer/$idLower/$versionLower/$fileName"
    $dest = Join-Path $feedDir $fileName
    Write-Host "Downloading $($pkg.Id) $($pkg.Version)"
    Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $dest
    $hash = (Get-FileHash -Algorithm SHA256 $dest).Hash.ToLowerInvariant()
    $manifest += "$hash  $fileName"
}

Set-Content -Path (Join-Path $feedDir 'SHA256SUMS.txt') -Value $manifest -Encoding ASCII
Set-Content -Path (Join-Path $feedDir 'README.txt') -Encoding UTF8 -Value @'
FPV OSD v4 offline NuGet feed
Avalonia 12.1.2
Target framework: net10.0
Runtime restored for dependency closure: linux-x64

Use as a local feed with:
  dotnet restore <project.csproj> --source <this-folder> --ignore-failed-sources
'@

if (Test-Path $OutputZip) { Remove-Item -Force $OutputZip }
Compress-Archive -Path (Join-Path $feedDir '*') -DestinationPath $OutputZip -CompressionLevel Optimal

$zipHash = (Get-FileHash -Algorithm SHA256 $OutputZip).Hash.ToLowerInvariant()
Write-Host ''
Write-Host "DONE: $OutputZip" -ForegroundColor Green
Write-Host "SHA256: $zipHash"
Write-Host "Upload this ZIP to the chat."

Remove-Item -Recurse -Force $work
