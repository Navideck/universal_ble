<#
.SYNOPSIS
    Runs one Windows hardware-in-the-loop test group against the nRF52 fixture.

.DESCRIPTION
    Starts a worker copy of this script, enforces a wall-clock budget, and
    writes the group log to $env:HIL_LOG_DIR, or next to this script when that
    variable is unset.

    -TimeoutSeconds is the single authority for the group budget. The CI
    workflow passes an explicit value per group; timing-sweeps needs the largest
    budget because its declared per-test timeouts add up to 34 minutes.

.PARAMETER Group
    Test group to run. The worker maps every group except `baseline` to the
    fault-injection suite and filters it with --plain-name.

.PARAMETER TimeoutSeconds
    Budget for the whole group, including the Flutter test build of the test
    bundle. The CI workflow warms the CMake/MSVC build once before the timed
    groups so this budget is not spent on a cold build.

.PARAMETER Worker
    Internal. Runs the test without the outer timeout wrapper.

.NOTES
    Invoke with an explicit execution policy when local scripts are restricted,
    for example:
        pwsh -NoProfile -ExecutionPolicy Bypass -File ./run_windows_hil_group.ps1 -Group baseline
#>
param(
    [Parameter(Mandatory)]
    [ValidateSet('baseline', 'connection-discovery', 'gatt-operations',
        'notifications-indications', 'mtu-resources', 'timing-sweeps')]
    [string]$Group,
    [ValidateRange(1, 3600)]
    [int]$TimeoutSeconds = 1800,
    [switch]$Worker
)

$ErrorActionPreference = 'Stop'
$logDirectory = if ($env:HIL_LOG_DIR) { $env:HIL_LOG_DIR } else { $PSScriptRoot }
$log = Join-Path $logDirectory "$Group-hil.log"

if (-not $Worker) {
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = Join-Path $PSHOME 'pwsh.exe'
    $start.WorkingDirectory = $PSScriptRoot
    $start.UseShellExecute = $false
    foreach ($argument in @('-NoProfile', '-NonInteractive', '-File',
        $PSCommandPath, '-Group', $Group, '-Worker')) {
        $start.ArgumentList.Add($argument)
    }
    $process = [Diagnostics.Process]::Start($start)
    try {
        if ($process.WaitForExit($TimeoutSeconds * 1000)) {
            exit $process.ExitCode
        }
        $message = "$Group timed out after $TimeoutSeconds seconds."
        Write-Host $message
        try {
            $process.Kill($true)
            if (-not $process.WaitForExit(10000)) {
                throw "The $Group test process did not exit after termination."
            }
        } finally {
            Add-Content -LiteralPath $log -Value $message
        }
        exit 124
    } finally {
        $process.Dispose()
    }
}

$PSNativeCommandUseErrorActionPreference = $false
$suite = if ($Group -eq 'baseline') { 'baseline' } else { 'fault_injection' }
$arguments = @('test', "integration_test/${suite}_hil_test.dart", '-d', 'windows',
    '--no-pub', '--reporter=expanded')
if ($Group -ne 'baseline') {
    $arguments += @('--plain-name', "[$Group]")
}
if ($env:HIL_DEVICE_ID) {
    $arguments += "--dart-define=HIL_DEVICE_ID=$env:HIL_DEVICE_ID"
}
flutter @arguments 2>&1 | Tee-Object -FilePath $log
exit $LASTEXITCODE
