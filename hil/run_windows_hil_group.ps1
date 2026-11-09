param(
    [Parameter(Mandatory)]
    [ValidateSet('baseline', 'connection-discovery', 'gatt-operations',
        'notifications-indications', 'mtu-resources', 'timing-sweeps')]
    [string]$Group,
    [ValidateRange(1, 3600)]
    [int]$TimeoutSeconds = 480,
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
