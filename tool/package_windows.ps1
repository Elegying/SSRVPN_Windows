[CmdletBinding()]
param(
  [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'
$projectRoot = [System.IO.Path]::GetFullPath(
  (Join-Path $PSScriptRoot '..')
)
$buildDir = Join-Path $projectRoot 'build\windows\x64\runner\Release'
$releaseDir = Join-Path $projectRoot 'SSRVPN_Windows_Release'
$zipPath = Join-Path $projectRoot 'SSRVPN_Windows_Release.zip'

function Repair-WindowsPluginLinks {
  param([Parameter(Mandatory = $true)][string]$Root)

  $dependenciesPath = Join-Path $Root '.flutter-plugins-dependencies'
  if (-not (Test-Path -LiteralPath $dependenciesPath -PathType Leaf)) {
    throw "Flutter plugin metadata not found: $dependenciesPath"
  }

  $metadata = Get-Content -LiteralPath $dependenciesPath -Raw |
    ConvertFrom-Json
  $plugins = @($metadata.plugins.windows)
  $linksDir = [System.IO.Path]::GetFullPath(
    (Join-Path $Root 'windows\flutter\ephemeral\.plugin_symlinks')
  )
  $expectedLinksDir = [System.IO.Path]::GetFullPath(
    (Join-Path $projectRoot 'windows\flutter\ephemeral\.plugin_symlinks')
  )
  if ($linksDir -ne $expectedLinksDir) {
    throw "Refusing to replace unexpected plugin directory: $linksDir"
  }

  if (Test-Path -LiteralPath $linksDir) {
    Remove-Item -LiteralPath $linksDir -Recurse -Force
  }
  New-Item -ItemType Directory -Path $linksDir | Out-Null

  foreach ($plugin in $plugins) {
    $linkPath = Join-Path $linksDir $plugin.name
    $targetPath = $plugin.path.TrimEnd('\')
    New-Item -ItemType SymbolicLink -Path $linkPath -Target $targetPath |
      Out-Null
  }
}

Push-Location $projectRoot
try {
  if (-not $SkipBuild) {
    $previousParallelLevel = $env:CMAKE_BUILD_PARALLEL_LEVEL
    $lockPath = Join-Path $projectRoot 'pubspec.lock'
    $lockExisted = Test-Path -LiteralPath $lockPath -PathType Leaf
    [byte[]]$lockBytes = $null
    if ($lockExisted) {
      $lockBytes = [System.IO.File]::ReadAllBytes($lockPath)
    }
    try {
      # New MSVC toolsets occasionally fail in STL headers under highly
      # parallel Flutter builds. A single build worker favors reproducibility.
      $env:CMAKE_BUILD_PARALLEL_LEVEL = '1'
      & flutter pub get
      if ($LASTEXITCODE -ne 0) {
        throw "flutter pub get failed with exit code $LASTEXITCODE"
      }
      Repair-WindowsPluginLinks -Root $projectRoot
      & flutter build windows --release --no-pub
      if ($LASTEXITCODE -ne 0) {
        throw "flutter build failed with exit code $LASTEXITCODE"
      }
    } finally {
      $env:CMAKE_BUILD_PARALLEL_LEVEL = $previousParallelLevel
      if ($lockExisted) {
        [System.IO.File]::WriteAllBytes($lockPath, $lockBytes)
      } elseif (Test-Path -LiteralPath $lockPath) {
        Remove-Item -LiteralPath $lockPath -Force
      }
    }
  }

  if (-not (Test-Path -LiteralPath $buildDir -PathType Container)) {
    throw "Release build directory not found: $buildDir"
  }

  $expectedReleaseDir = [System.IO.Path]::GetFullPath(
    (Join-Path $projectRoot 'SSRVPN_Windows_Release')
  )
  if ([System.IO.Path]::GetFullPath($releaseDir) -ne $expectedReleaseDir) {
    throw "Refusing to clean unexpected release directory: $releaseDir"
  }

  if (Test-Path -LiteralPath $releaseDir) {
    Remove-Item -LiteralPath $releaseDir -Recurse -Force
  }
  New-Item -ItemType Directory -Path $releaseDir | Out-Null
  Copy-Item -Path (Join-Path $buildDir '*') -Destination $releaseDir `
    -Recurse -Force
  $portableReadmeName = [string]::Concat(
    [char]0x4F7F,
    [char]0x7528,
    [char]0x6559,
    [char]0x7A0B,
    '.txt'
  )
  Copy-Item -LiteralPath (Join-Path $projectRoot 'PORTABLE_README.txt') `
    -Destination (Join-Path $releaseDir $portableReadmeName)

  $requiredFiles = @(
    'ssrvpn_windows.exe',
    'mihomo.exe',
    'flutter_windows.dll',
    'msvcp140.dll',
    'vcruntime140.dll',
    'vcruntime140_1.dll',
    'data\app.so',
    'data\icudtl.dat',
    'data\flutter_assets\assets\geoip.metadb.gz'
  )
  foreach ($relativePath in $requiredFiles) {
    $path = Join-Path $releaseDir $relativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
      throw "Required release file is missing: $relativePath"
    }
  }

  $hashLines = Get-ChildItem -LiteralPath $releaseDir -File |
    Where-Object { $_.Extension -in '.exe', '.dll' } |
    Sort-Object Name |
    ForEach-Object {
      $hash = Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256
      "$($hash.Hash)  $($_.Name)"
    }
  $hashLines | Set-Content -LiteralPath (
    Join-Path $releaseDir 'SHA256SUMS.txt'
  ) -Encoding UTF8

  if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
  }
  Compress-Archive -LiteralPath $releaseDir -DestinationPath $zipPath `
    -CompressionLevel Optimal

  $zipHash = Get-FileHash -LiteralPath $zipPath -Algorithm SHA256
  Write-Host "Release: $releaseDir"
  Write-Host "ZIP:     $zipPath"
  Write-Host "SHA256:  $($zipHash.Hash)"
} finally {
  Pop-Location
}
