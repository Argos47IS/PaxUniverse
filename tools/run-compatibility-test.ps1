param(
    [ValidateSet('automatic','atlas','interface','reload','validate')]
    [string]$Stage = 'automatic',
    [string]$GameDirectory = (Join-Path $env:LOCALAPPDATA 'Programs/Pax Universe'),
    [switch]$UseLocalLicense
)
$ErrorActionPreference = 'Stop'
$workspace = Split-Path -Parent $PSScriptRoot
$game = (Resolve-Path -LiteralPath $GameDirectory).Path
$patch = Join-Path $game 'PaxUniverse.patch.pck'
$signature = (Get-FileHash -LiteralPath $patch).Hash.Substring(0,12).ToLowerInvariant()
$qa = Join-Path $workspace ('.local/compat-game-' + $signature)
$output = Join-Path $workspace ('previews/compatibility-' + $signature + '/' + $Stage)
$profile = Join-Path $env:APPDATA 'Pax Universe Atlas QA'
New-Item -ItemType Directory -Force -Path $qa, $output, $profile, (Join-Path $qa 'mods') | Out-Null
foreach ($name in @('PaxUniverse.exe','PaxUniverse.pck','PaxUniverse.patch.pck','installed.json','libgodot-xterm.windows.template_release.x86_64.dll')) {
    $source = Join-Path $game $name
    if (!(Test-Path -LiteralPath $source)) { continue }
    $target = Join-Path $qa $name
    if (!(Test-Path -LiteralPath $target)) { Copy-Item -LiteralPath $source -Destination $target }
    elseif ((Get-FileHash -LiteralPath $source).Hash -ne (Get-FileHash -LiteralPath $target).Hash) {
        throw "Snapshot changed: $target. Preserve this QA directory and start a fresh snapshot."
    }
}
$packages = @()
foreach ($id in @('earth_atlas','pax_interface')) {
    $manifest = Get-Content -LiteralPath (Join-Path $workspace "mods/$id/mod.json") -Raw | ConvertFrom-Json
    $package = Join-Path $workspace ("dist/$id/$id-" + $manifest.version + '.zip')
    if (!(Test-Path -LiteralPath $package)) { throw "Build package first: $package" }
    $packages += Split-Path -Leaf $package
    Copy-Item -LiteralPath $package -Destination (Join-Path $qa 'mods') -Force
}
$extra = Get-ChildItem -LiteralPath (Join-Path $qa 'mods') -File | Where-Object { $_.Name -notin $packages }
if ($extra) { throw 'QA mods directory contains additional packages; use a clean snapshot.' }
$hostScript = (Join-Path $PSScriptRoot 'compatibility_host.gd').Replace('\','/')
$configuration = @"
[application]
config/name="Pax Universe Atlas QA"
config/use_custom_user_dir=true
config/custom_user_dir_name="Pax Universe Atlas QA"
[autoload]
CompatHost="*$hostScript"
[accessibility]
general/accessibility_support=2
[input_devices]
pen_tablet/driver.windows="dummy"
"@
[IO.File]::WriteAllText((Join-Path $qa 'override.cfg'), $configuration, [Text.UTF8Encoding]::new($false))
$backups = @{}
foreach ($name in @('mods.json','settings.json')) {
    $path = Join-Path $profile $name
    $backups[$path] = if (Test-Path -LiteralPath $path) { [IO.File]::ReadAllBytes($path) } else { $null }
}
$license = Join-Path $profile 'license.json'
$copiedLicense = $false
try {
    if (!(Test-Path -LiteralPath $license)) {
        if (!$UseLocalLicense) { throw 'QA needs a valid license. Use -UseLocalLicense to copy your existing local license on this computer; it is removed afterward.' }
        Copy-Item -LiteralPath (Join-Path $env:APPDATA 'Pax Universe/license.json') -Destination $license
        $copiedLicense = $true
    }
    [IO.File]::WriteAllText((Join-Path $profile 'mods.json'), '{"disabled":[],"order":["earth_atlas","pax_interface"],"seen":["earth_atlas","pax_interface"]}')
    [IO.File]::WriteAllText((Join-Path $profile 'settings.json'), '{"язык":"ru","заставка":false,"провайдеры":{"мозг":{"режим":"выкл"}}}')
    $env:PAX_COMPAT_OUTPUT = $output
    $env:PAX_UI_TEST_OUTPUT = $output
    $env:PAX_COMPAT_STAGE = $Stage
    $process = Start-Process -FilePath (Join-Path $qa 'PaxUniverse.exe') -WorkingDirectory $qa -WindowStyle Hidden -PassThru -ArgumentList @('--resolution','1920x1080','--quit-after','30000') -RedirectStandardOutput (Join-Path $output 'runtime.out.log') -RedirectStandardError (Join-Path $output 'runtime.err.log')
    if (!$process.WaitForExit(600000)) {
        Stop-Process -Id $process.Id
        throw 'QA timed out; logs are retained.'
    }
    $report = Get-Content -LiteralPath (Join-Path $output 'compatibility-report.json') -Raw | ConvertFrom-Json
    if ($process.ExitCode -ne 0 -or !$report.ok) { throw "Compatibility check failed. Read $output" }
    if ($Stage -eq 'interface') {
        $interfaceReport = Get-Content -LiteralPath (Join-Path $output 'live-test-report.json') -Raw | ConvertFrom-Json
        if (!$interfaceReport.ok -or $interfaceReport.assertion_count -lt 500) { throw 'Incomplete or failed HUD checks.' }
    }
    $errors = Get-Content -LiteralPath (Join-Path $output 'runtime.err.log') -Raw
    if ($errors -match 'SCRIPT ERROR|Parse Error|COMPAT_FAIL') { throw "Runtime errors. Read $output" }
    Write-Output ("PASS $Stage; game=" + $report.version + "; reports=$output")
} finally {
    foreach ($path in $backups.Keys) {
        if ($null -ne $backups[$path]) { [IO.File]::WriteAllBytes($path, $backups[$path]) }
        elseif (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path }
    }
    if ($copiedLicense -and (Test-Path -LiteralPath $license)) { Remove-Item -LiteralPath $license }
}
