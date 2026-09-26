param(
    [string]$Stage = 'probe',
    [string]$GameDirectory = (Join-Path $env:LOCALAPPDATA 'Programs/Pax Universe'),
    [switch]$Headless,
    [switch]$Validate
)
$ErrorActionPreference = 'Stop'
$workspace = Split-Path -Parent $PSScriptRoot
$source = (Resolve-Path -LiteralPath $GameDirectory).Path
if ($Stage -notmatch '^[a-zA-Z0-9_-]+$') { throw 'Stage must be a simple directory name.' }
$qa = Join-Path $workspace '.local/test-game-units'
$output = Join-Path $workspace ('previews/pax-units/' + $Stage)
New-Item -ItemType Directory -Force -Path $qa, $output, (Join-Path $qa 'mods') | Out-Null
foreach ($file in @('PaxUniverse.exe','PaxUniverse.pck','PaxUniverse.patch.pck')) {
    $target = Join-Path $qa $file
    $sourceFile = Join-Path $source $file
    if (!(Test-Path -LiteralPath $sourceFile)) {
        if ($file -eq 'PaxUniverse.patch.pck') { continue }
        throw "Missing game file: $sourceFile"
    }
    if (!(Test-Path -LiteralPath $target)) {
        try { New-Item -ItemType HardLink -Path $target -Target $sourceFile | Out-Null }
        catch { Copy-Item -LiteralPath $sourceFile -Destination $target }
    } elseif ((Get-FileHash -LiteralPath $target).Hash -ne (Get-FileHash -LiteralPath $sourceFile).Hash) {
        throw "QA game copy is outdated: $target. Use a fresh QA directory before testing the updated game."
    }
}
$config = @'
[application]
config/name="Pax Universe Units QA"
config/use_custom_user_dir=true
config/custom_user_dir_name="Pax Universe Units QA"
[accessibility]
general/accessibility_support=2
[input_devices]
pen_tablet/driver.windows="dummy"
'@
[IO.File]::WriteAllText((Join-Path $qa 'override.cfg'), $config, [Text.UTF8Encoding]::new($false))
Copy-Item -LiteralPath (Join-Path $workspace 'mods/pax_units') -Destination (Join-Path $qa 'mods') -Recurse -Force
foreach ($package in @('earth_atlas-0.2.0.zip','pax_interface-0.3.0.zip')) {
    $modId = if ($package.StartsWith('earth_atlas-')) { 'earth_atlas' } else { 'pax_interface' }
    $packageSource = Join-Path $workspace ('dist/' + $modId + '/' + $package)
    if (!(Test-Path -LiteralPath $packageSource)) { throw "Missing release package: $packageSource" }
    Copy-Item -LiteralPath $packageSource -Destination (Join-Path $qa 'mods') -Force
}
$env:PAX_UNITS_OUTPUT = $output
$env:PAX_UNITS_STAGE = $Stage
$arguments = @('--resolution', '1920x1080', '--position', '0,0')
if ($Headless -or $Validate) { $arguments += '--headless' }
if ($Validate) { $arguments += @('--','--check-mods','pax_units') } else { $arguments += @('--','--units-live-test') }
$process = Start-Process -FilePath (Join-Path $qa 'PaxUniverse.exe') -ArgumentList $arguments -WorkingDirectory $qa -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $output 'runtime.out.log') -RedirectStandardError (Join-Path $output 'runtime.err.log')
Write-Output ('QA_PID=' + $process.Id)
$process.WaitForExit()
Get-Content -LiteralPath (Join-Path $output 'runtime.out.log') -Tail 16
Get-Content -LiteralPath (Join-Path $output 'runtime.err.log') -Tail 40
if ($Validate -and $process.ExitCode -eq 0) {
    $stdout = Get-Content -LiteralPath (Join-Path $output 'runtime.out.log') -Raw
    $stderr = Get-Content -LiteralPath (Join-Path $output 'runtime.err.log') -Raw
    if ($stdout -notmatch '\[pax_units\].*checked\s+[1-9][0-9]*\s+files' -or $stderr -match "Couldn't open directory.*res://mods/pax_units") {
        Write-Error 'The validator did not inspect a mounted pax_units mod. Zero checked files is not a successful validation.' -ErrorAction Continue
        exit 3
    }
}
exit $process.ExitCode
