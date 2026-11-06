[CmdletBinding()]
param(
    [string]$Swiftc = ''
)

# Native compilers write warnings to stderr, which would become a terminating
# error under 'Stop'. Compile and run results are checked through exit codes.
$ErrorActionPreference = 'Continue'

$root = Split-Path -Parent $PSScriptRoot
$bin = Join-Path $PSScriptRoot 'bin'
New-Item -ItemType Directory -Force -Path $bin | Out-Null

if ([string]::IsNullOrWhiteSpace($Swiftc)) {
    $command = Get-Command swiftc -ErrorAction SilentlyContinue
    if (-not $command) {
        Write-Host 'error: swiftc was not found on PATH. Pass -Swiftc <path to swiftc.exe>.' -ForegroundColor Red
        exit 1
    }
    $Swiftc = $command.Source
}

$sources = @(
    (Join-Path $root 'App\Design\AccessibilityText.swift'),
    (Join-Path $root 'App\Design\NumericDisplay.swift'),
    (Join-Path $root 'App\Models\SpeedUnit.swift'),
    (Join-Path $root 'App\Services\GPSStatus.swift'),
    (Join-Path $root 'App\Services\Engine\MotionMath.swift'),
    (Join-Path $root 'App\Services\Engine\TripRecorder.swift'),
    (Join-Path $root 'App\Services\Demo\DemoDrive.swift'),
    (Join-Path $root 'App\Services\Demo\DemoSession.swift'),
    (Join-Path $root 'App\Services\Engine\SpeedEngine.swift'),
    (Join-Path $PSScriptRoot 'SpeedEngineTests.swift')
)

& $Swiftc -o (Join-Path $bin 'SpeedEngineTests.exe') @sources 2> (Join-Path $PSScriptRoot 'build.log')
$compileExit = $LASTEXITCODE
if ($compileExit -ne 0) {
    Get-Content (Join-Path $PSScriptRoot 'build.log')
    exit $compileExit
}

& (Join-Path $bin 'SpeedEngineTests.exe')
exit $LASTEXITCODE
