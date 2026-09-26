param(
    [switch]$UseLocalLicense,
    [switch]$SmokeTest,
    [ValidateRange(120,3600)][int]$SmokeFrames = 1200,
    [ValidateRange(30,180)][int]$SmokeTimeoutSeconds = 90,
    [switch]$SmokeWithoutMemory
)
$ErrorActionPreference = 'Stop'
if ($SmokeWithoutMemory -and !$SmokeTest) { throw 'SmokeWithoutMemory is a temporary diagnostic mode and requires SmokeTest.' }
$workspace = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$game = Join-Path $workspace '.local/refactor-game'
$root = Join-Path $workspace '.local/Pax Universe Refactor'
$profile = Join-Path $env:APPDATA 'Pax Universe Refactor QA'
if (!(Test-Path -LiteralPath (Join-Path $root 'original-inventory.json'))) { throw 'Create the verified experiment copy first.' }
if (!(Test-Path -LiteralPath (Join-Path $game 'mods/paxmemory/mod.json'))) { throw 'Install the checked memory mod into the experimental copy first.' }
foreach ($active in Get-Process -Name PaxUniverse -ErrorAction SilentlyContinue) {
    if ($active.Path -eq (Join-Path $game 'PaxUniverse.exe')) { throw 'The experiment is already running; do not change its profile during a run.' }
}
New-Item -ItemType Directory -Path $profile,(Join-Path $profile 'mods') -Force | Out-Null
foreach ($package in @('earth_atlas/earth_atlas-0.2.1.zip','pax_interface/pax_interface-0.3.1.zip')) {
    $source = Join-Path (Join-Path $workspace 'dist') $package
    $destination = Join-Path (Join-Path $profile 'mods') ([IO.Path]::GetFileName($package))
    if (!(Test-Path -LiteralPath $destination)) { Copy-Item -LiteralPath $source -Destination $destination }
}
# Only this isolated profile is configured. Normal installation settings are never read or written.
$config = @'
[application]
config/name="Pax Universe Refactor QA"
config/use_custom_user_dir=true
config/custom_user_dir_name="Pax Universe Refactor QA"
[accessibility]
general/accessibility_support=2
[input_devices]
pen_tablet/driver.windows="dummy"
'@
[IO.File]::WriteAllText((Join-Path $game 'override.cfg'),$config,[Text.UTF8Encoding]::new($false))
if (!(Test-Path -LiteralPath (Join-Path $profile 'settings.json'))) {
    [IO.File]::WriteAllText((Join-Path $profile 'settings.json'),'{"язык":"ru","заставка":false,"провайдеры":{"мозг":{"режим":"выкл"}}}')
}
if (!(Test-Path -LiteralPath (Join-Path $profile 'mods.json'))) {
    [IO.File]::WriteAllText((Join-Path $profile 'mods.json'),'{"disabled":[],"order":["earth_atlas","pax_interface","pax_memory"],"seen":["earth_atlas","pax_interface","pax_memory"]}')
}
$license = Join-Path $profile 'license.json'
$copied = $false
$modsPath = Join-Path $profile 'mods.json'
$modsBackup = $null
try {
    if ($SmokeWithoutMemory) {
        $modsBackup = [IO.File]::ReadAllBytes($modsPath)
        $modState = Get-Content -LiteralPath $modsPath -Raw | ConvertFrom-Json
        [string[]]$disabled = @($modState.disabled | Where-Object { $_ -is [string] -and $_ -ne 'pax_memory' }) + @('pax_memory')
        $modState | Add-Member -MemberType NoteProperty -Name disabled -Value $disabled -Force
        $modState | ConvertTo-Json -Depth 12 -Compress | Set-Content -LiteralPath $modsPath -Encoding utf8
    }
    if ($UseLocalLicense -and !(Test-Path -LiteralPath $license)) {
        Copy-Item -LiteralPath (Join-Path $env:APPDATA 'Pax Universe/license.json') -Destination $license
        $copied = $true
    }
    $arguments = @('--resolution','1920x1080')
    $logRoot = $root
    if ($SmokeTest) {
        $arguments += @('--quit-after',([string]$SmokeFrames),'--verbose')
        $logRoot = Join-Path $root ('runs/launcher-smoke-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
        New-Item -ItemType Directory -Path $logRoot | Out-Null
    }
    $stdout = Join-Path $logRoot 'launcher.out.log'
    $stderr = Join-Path $logRoot 'launcher.err.log'
    $started = [Diagnostics.Stopwatch]::StartNew()
    $process = Start-Process -FilePath (Join-Path $game 'PaxUniverse.exe') -WorkingDirectory $game -WindowStyle Hidden -ArgumentList $arguments -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    $timedOut = $false
    if ($SmokeTest) {
        if (!$process.WaitForExit($SmokeTimeoutSeconds * 1000)) {
            $timedOut = $true
            Stop-Process -Id $process.Id
            $process.WaitForExit()
        }
    } else { $process.WaitForExit() }
    $stderrText = Get-Content -LiteralPath $stderr -Raw
    $runtimeErrors = @([regex]::Matches([string]$stderrText, '(?m)^ERROR:|SCRIPT ERROR'))
    $shutdownResources = [string]$stderrText -match 'resources still in use at exit'
    if ($SmokeTest) {
        $status = if ($timedOut) { 'timeout' } elseif ($process.ExitCode -ne 0) { 'process_error' } elseif ($runtimeErrors.Count -gt 0) { 'runtime_error' } else { 'clean_automatic_exit' }
        @{ status=$status; exit_code=$process.ExitCode; elapsed_ms=$started.Elapsed.TotalMilliseconds; requested_frames=$SmokeFrames; without_memory=[bool]$SmokeWithoutMemory; runtime_error_count=$runtimeErrors.Count; shutdown_resource_error=$shutdownResources; objectdb_leak_warning=([string]$stderrText -match 'ObjectDB instances were leaked at exit'); menu_ready_verified=$false; automatic_exit=$true } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $logRoot 'launcher-smoke.json') -Encoding utf8
        Write-Output "Smoke result: $status; private diagnostics: $logRoot"
    }
    if ($timedOut) { throw 'Experiment launcher smoke test timed out; diagnostics retained.' }
    if ($process.ExitCode -ne 0) { throw "Experiment exited with $($process.ExitCode). See private launcher logs." }
    if ($runtimeErrors.Count -gt 0) { throw 'Godot errors in the experiment launcher; a zero exit code is not a successful smoke test.' }
    Write-Output 'Experiment closed normally; original installation was not changed.'
} finally {
    if ($null -ne $modsBackup) { [IO.File]::WriteAllBytes($modsPath,$modsBackup) }
    if ($copied -and (Test-Path -LiteralPath $license)) { Remove-Item -LiteralPath $license }
}
