param(
    [ValidateSet('audit','baseline','ai_probe','ai_integration')][string]$Stage = 'audit',
    [string]$RunName = 'audit',
    [switch]$WithMods,
    [switch]$WithoutMemory,
    [switch]$UseLocalLicense
)
$ErrorActionPreference = 'Stop'
if ($RunName -notmatch '^[a-zA-Z0-9_-]+$') { throw 'Invalid run name' }
$workspace = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$root = Join-Path $workspace '.local/Pax Universe Refactor'
$game = Join-Path $workspace '.local/refactor-game'
$output = Join-Path $root ('runs/' + $RunName)
$profile = Join-Path $env:APPDATA 'Pax Universe Refactor QA'
if (!(Test-Path -LiteralPath (Join-Path $root 'original-inventory.json'))) { throw 'Create and verify the separate copy first.' }
if (Test-Path -LiteralPath $output) { throw 'Run already exists; use a new RunName.' }
New-Item -ItemType Directory -Force -Path $profile,$output,(Join-Path $profile 'mod_cache'),(Join-Path $profile 'mod_settings') | Out-Null
$hostScript = (Join-Path $PSScriptRoot ($Stage + '_host.gd')).Replace('\','/')
if (!(Test-Path -LiteralPath $hostScript)) { throw 'Missing test host' }
$override = @"
[application]
config/name="Pax Universe Refactor QA"
config/use_custom_user_dir=true
config/custom_user_dir_name="Pax Universe Refactor QA"
[autoload]
RefactorHost="*$hostScript"
[accessibility]
general/accessibility_support=2
[input_devices]
pen_tablet/driver.windows="dummy"
"@
[IO.File]::WriteAllText((Join-Path $game 'override.cfg'),$override,[Text.UTF8Encoding]::new($false))
$license = Join-Path $profile 'license.json'
$copiedLicense = $false
$backups = @{}
foreach ($name in @('settings.json','mods.json')) {
    $path = Join-Path $profile $name
    $backups[$path] = if (Test-Path -LiteralPath $path) { [IO.File]::ReadAllBytes($path) } else { $null }
}
try {
    if ($UseLocalLicense -and !(Test-Path -LiteralPath $license)) {
        Copy-Item -LiteralPath (Join-Path $env:APPDATA 'Pax Universe/license.json') -Destination $license
        $copiedLicense = $true
    }
    [IO.File]::WriteAllText((Join-Path $profile 'settings.json'),'{"язык":"ru","заставка":false,"провайдеры":{"мозг":{"режим":"выкл"}}}')
    [string[]]$disabled = @()
    if (!$WithMods) { $disabled = @('earth_atlas','pax_interface','pax_memory') }
    elseif ($WithoutMemory) { $disabled = @('pax_memory') }
    @{ disabled = $disabled; order = @('earth_atlas','pax_interface','pax_memory'); seen = @('earth_atlas','pax_interface','pax_memory') } | ConvertTo-Json -Compress | Set-Content -LiteralPath (Join-Path $profile 'mods.json') -Encoding utf8
    $writtenMods = Get-Content -LiteralPath (Join-Path $profile 'mods.json') -Raw | ConvertFrom-Json
    if ($writtenMods.disabled -isnot [Array]) { throw 'Invalid QA mods.json: disabled must be a JSON array, including when empty.' }
    $env:PAX_REFACTOR_OUTPUT = $output
    $env:PAX_REFACTOR_MODS = if ($WithMods) { '1' } else { '0' }
    $started = [Diagnostics.Stopwatch]::StartNew()
    $process = Start-Process -FilePath (Join-Path $game 'PaxUniverse.exe') -WorkingDirectory $game -WindowStyle Hidden -PassThru -ArgumentList @('--resolution','1920x1080','--quit-after','30000') -RedirectStandardOutput (Join-Path $output 'runtime.out.log') -RedirectStandardError (Join-Path $output 'runtime.err.log')
    $samples = @()
    while (!$process.WaitForExit(500)) {
        $process.Refresh()
        $samples += @{ wall_ms = $started.Elapsed.TotalMilliseconds; cpu_seconds = $process.TotalProcessorTime.TotalSeconds; working_set_bytes = $process.WorkingSet64; private_bytes = $process.PrivateMemorySize64 }
        if ($started.Elapsed.TotalSeconds -gt 240) { Stop-Process -Id $process.Id; throw 'Experiment timeout; logs retained.' }
    }
    @{ exit_code = $process.ExitCode; elapsed_ms = $started.Elapsed.TotalMilliseconds; logical_processors = [Environment]::ProcessorCount; samples = $samples } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $output 'process-metrics.json') -Encoding utf8
    if ($process.ExitCode -ne 0) { throw "Game failed: $($process.ExitCode); $output" }
    $errors = Get-Content -LiteralPath (Join-Path $output 'runtime.err.log') -Raw
    if ($errors -match '(?m)^ERROR:|SCRIPT ERROR|Parse Error|REFACTOR_FAIL') { throw "Runtime errors: $output" }
    $reportName = switch ($Stage) { 'audit' { 'runtime-inventory.json' }; 'baseline' { 'baseline.json' }; 'ai_probe' { 'ai-probe-private.json' }; 'ai_integration' { 'ai-integration-private.json' } }
    if (!(Test-Path -LiteralPath (Join-Path $output $reportName))) { throw 'Expected report absent; exit code alone is not a pass.' }
    Write-Output "PASS $Stage : $output"
} finally {
    foreach ($path in $backups.Keys) {
        if ($null -ne $backups[$path]) { [IO.File]::WriteAllBytes($path,$backups[$path]) }
        elseif (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path }
    }
    if ($copiedLicense -and (Test-Path -LiteralPath $license)) { Remove-Item -LiteralPath $license }
}
