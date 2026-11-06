<#
.SYNOPSIS
Builds artifacts/Velora.ipa with WindowsIPABuilder.

.DESCRIPTION
Resolves the project root from the script location, loads BuildConfig.local.ps1
from the project root and validates every configured tool before building.
Generated output always lands in artifacts/.

.PARAMETER ValidateOnly
Prints the resolved configuration and exits without invoking the builder.
#>
[CmdletBinding()]
param(
    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$configPath  = Join-Path $projectRoot 'BuildConfig.local.ps1'
$artifactDir = Join-Path $projectRoot 'artifacts'
$workDir     = Join-Path $artifactDir 'work'
$logPath     = Join-Path $artifactDir 'build.log'
$ipaPath     = Join-Path $artifactDir 'Velora.ipa'

# Velora is the product name; the executable keeps the historical name so the
# bundle layout and the signing assumptions stay stable.
$appName        = 'Velora'
$executableName = 'Speedometer'
$iconPath       = Join-Path $projectRoot 'App\Resources\VeloraIcon.png'
$privacyManifest = Join-Path $projectRoot 'App\Resources\PrivacyInfo.xcprivacy'

function Stop-WithError {
    param([string]$Message)
    Write-Host "error: $Message" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
    Stop-WithError ("Build configuration missing: {0}`nCopy BuildConfig.example.ps1 to BuildConfig.local.ps1 and fill in the tool paths." -f $configPath)
}

$config = & $configPath
if ($config -isnot [System.Collections.IDictionary]) {
    Stop-WithError 'BuildConfig.local.ps1 must return a hashtable.'
}

# IosSdk points to a directory, every other required entry to an executable.
$directoryKeys = @('IosSdk')
$fileKeys      = @('IpaBuilderCli', 'Ldid', 'Swiftc', 'Clang')

$problems = @()
foreach ($key in $directoryKeys + $fileKeys) {
    $value = $config[$key]
    if ([string]::IsNullOrWhiteSpace([string]$value)) {
        $problems += "$key is not configured"
        continue
    }
    $kind = if ($directoryKeys -contains $key) { 'Container' } else { 'Leaf' }
    try {
        $exists = Test-Path -LiteralPath $value -PathType $kind
    } catch {
        $problems += "$key is not a valid path: $value"
        continue
    }
    if (-not $exists) {
        $problems += "$key not found: $value"
    }
}

if ($problems.Count -gt 0) {
    Stop-WithError ("Build configuration is incomplete:`n  - " + ($problems -join "`n  - ") + "`nUpdate BuildConfig.local.ps1.")
}

if ($ValidateOnly) {
    Write-Host 'Build configuration is valid.'
    Write-Host ("  Project root : {0}" -f $projectRoot)
    Write-Host ("  Builder CLI  : {0}" -f $config.IpaBuilderCli)
    Write-Host ("  iOS SDK      : {0}" -f $config.IosSdk)
    Write-Host ("  ldid         : {0}" -f $config.Ldid)
    Write-Host ("  swiftc       : {0}" -f $config.Swiftc)
    Write-Host ("  clang        : {0}" -f $config.Clang)
    exit 0
}

New-Item -ItemType Directory -Force -Path $artifactDir, $workDir | Out-Null

if (-not [string]::IsNullOrWhiteSpace([string]$config.SwiftModuleCache)) {
    New-Item -ItemType Directory -Force -Path $config.SwiftModuleCache | Out-Null
    $env:IPABUILDER_SWIFT_MODULE_CACHE = $config.SwiftModuleCache
}

$appSource = Join-Path $projectRoot 'App'
if (-not (Test-Path -LiteralPath $appSource -PathType Container)) {
    Stop-WithError "Application sources not found: $appSource"
}

if (-not (Test-Path -LiteralPath $iconPath -PathType Leaf)) {
    Stop-WithError "App icon not found: $iconPath"
}

if (-not (Test-Path -LiteralPath $privacyManifest -PathType Leaf)) {
    Stop-WithError "Privacy manifest not found: $privacyManifest"
}

# English text for the iOS location permission prompt.
$locationUsage = 'Velora uses your location to measure speed and distance during an active trip. Your location is processed locally on your device.'

$arguments = @(
    'build',
    '--source', $appSource,
    '--name', $appName,
    '--executable', $executableName,
    '--icon', $iconPath,
    '--bundle-id', 'com.velora.app',
    '--min-ios', '26.0',
    '--device', 'iphone',
    '--framework', 'SwiftUI',
    '--framework', 'UIKit',
    '--framework', 'Foundation',
    '--framework', 'Combine',
    '--framework', 'CoreLocation',
    '--location-usage-description', $locationUsage,
    '--output', $workDir,
    '--clang', $config.Clang,
    '--sdk', $config.IosSdk,
    '--ldid', $config.Ldid,
    '--swiftc', $config.Swiftc
)

# The builder writes compiler warnings to stderr, which 'Stop' would turn into
# a terminating error. Relax the preference for the invocation and decide on
# the process exit code instead.
$previousPreference = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
& $config.IpaBuilderCli @arguments *>&1 | Out-File -FilePath $logPath -Encoding utf8
$exitCode = $LASTEXITCODE
$ErrorActionPreference = $previousPreference

if ($exitCode -ne 0) {
    Stop-WithError "IPA build failed with exit code $exitCode. See $logPath."
}

$builtIpa = Join-Path $workDir "$appName.ipa"
if (-not (Test-Path -LiteralPath $builtIpa -PathType Leaf)) {
    Stop-WithError "Builder finished but produced no IPA at $builtIpa. See $logPath."
}

# The builder has no resource parameter, so the privacy manifest is placed in the
# packaged bundle here. The executable is signed again afterwards with the same
# ad-hoc command the builder uses, so no resource arrives after the final
# signing step without a matching signature pass.
Add-Type -AssemblyName System.IO.Compression.FileSystem

$repackDir = Join-Path $workDir 'repack'
if (Test-Path -LiteralPath $repackDir) {
    Remove-Item -LiteralPath $repackDir -Recurse -Force
}
[System.IO.Compression.ZipFile]::ExtractToDirectory($builtIpa, $repackDir)

$appBundle = Get-ChildItem -Path (Join-Path $repackDir 'Payload') -Directory | Select-Object -First 1
if (-not $appBundle) {
    Stop-WithError 'The built IPA contains no application bundle under Payload.'
}

Copy-Item -LiteralPath $privacyManifest -Destination (Join-Path $appBundle.FullName 'PrivacyInfo.xcprivacy') -Force

$previousPreference = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
Push-Location -LiteralPath $appBundle.FullName
try {
    & $config.Ldid -S $executableName 2>&1 | Out-File -FilePath $logPath -Encoding utf8 -Append
    $signExit = $LASTEXITCODE
}
finally {
    Pop-Location
}
$ErrorActionPreference = $previousPreference

if ($signExit -ne 0) {
    Stop-WithError "Re-signing the app bundle failed with exit code $signExit. See $logPath."
}

Remove-Item -LiteralPath $builtIpa -Force
[System.IO.Compression.ZipFile]::CreateFromDirectory(
    $repackDir,
    $builtIpa,
    [System.IO.Compression.CompressionLevel]::Optimal,
    $false)
Remove-Item -LiteralPath $repackDir -Recurse -Force

Move-Item -LiteralPath $builtIpa -Destination $ipaPath -Force
Write-Host ("IPA written to {0}" -f $ipaPath)
