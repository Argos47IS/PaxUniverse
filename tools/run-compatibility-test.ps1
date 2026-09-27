param(
    [ValidateSet('automatic','atlas','interface','reload','validate','coexist','nativeextras')]
    [string]$Stage = 'automatic',
    [string]$GameDirectory = (Join-Path $env:LOCALAPPDATA 'Programs/Pax Universe'),
    # Test the actual unpacked installations, retaining their physical folder names.
    [string]$FolderModsDirectory,
    # Test the current store ZIPs without changing their filenames.
    [string]$InstalledModsDirectory,
    [switch]$IncludeOtherMods,
    [ValidatePattern("^[a-zA-Z0-9_-]*$")][string]$RunLabel,
    [switch]$UseLocalLicense,
    [switch]$VerboseEngine,
    [switch]$Headless
)
$ErrorActionPreference = 'Stop'
if ($FolderModsDirectory -and $InstalledModsDirectory) { throw 'Choose folders or installed ZIPs, not both.' }
if ($IncludeOtherMods -and !$InstalledModsDirectory) { throw 'IncludeOtherMods requires installed ZIPs.' }
if ($Stage -eq 'nativeextras' -and !$IncludeOtherMods) { throw 'Native extras control requires the installed third-party packages.' }
$workspace = Split-Path -Parent $PSScriptRoot
$game = (Resolve-Path -LiteralPath $GameDirectory).Path
$patch = Join-Path $game 'PaxUniverse.patch.pck'
$signature = (Get-FileHash -LiteralPath $patch).Hash.Substring(0,12).ToLowerInvariant()
if ($FolderModsDirectory) { $signature += '-folders' }
if ($InstalledModsDirectory) { $signature += '-installed' }
if ($IncludeOtherMods) { $signature += '-coexist' }
$qa = Join-Path $workspace ('.local/compat-game-' + $signature)
$outputStage = if ($RunLabel) { $Stage + '-' + $RunLabel } else { $Stage }
$output = Join-Path $workspace ('previews/compatibility-' + $signature + '/' + $outputStage)
if (Test-Path -LiteralPath (Join-Path $output 'runtime.out.log')) { throw 'Preserve the previous run; choose a new RunLabel.' }
$profile = Join-Path $env:APPDATA 'Pax Universe Atlas QA'
New-Item -ItemType Directory -Force -Path $qa, $output, $profile, (Join-Path $qa 'mods') | Out-Null
foreach ($name in @('PaxUniverse.exe','PaxUniverse.pck','PaxUniverse.patch.pck','installed.json','libgodot-xterm.windows.template_release.x86_64.dll')) {
    $source = Join-Path $game $name
    if (!(Test-Path -LiteralPath $source)) { continue }
    $target = Join-Path $qa $name
    if (!(Test-Path -LiteralPath $target)) { Copy-Item -LiteralPath $source -Destination $target }
    # The launcher updates installed.json integrity timestamps during a run.
    # Keep the first metadata snapshot; executable resources must still match.
    elseif ($name -ne 'installed.json' -and (Get-FileHash -LiteralPath $source).Hash -ne (Get-FileHash -LiteralPath $target).Hash) {
        throw "Snapshot changed: $target. Preserve this QA directory and start a fresh snapshot."
    }
}
$ids = @('earth_atlas','pax_interface')
$packages = @()
$folderSources = @{}
$zipSources = @{}
$installations = @()
$profileMods = Join-Path $profile 'mods'
if (Test-Path -LiteralPath $profileMods) {
    throw 'QA profile already has a mods directory; preserve it before running an isolated test.'
}
if ($FolderModsDirectory) {
    $folderRoot = (Resolve-Path -LiteralPath $FolderModsDirectory).Path
    foreach ($folder in Get-ChildItem -LiteralPath $folderRoot -Directory) {
        $manifestPath = Join-Path $folder.FullName 'mod.json'
        if (!(Test-Path -LiteralPath $manifestPath)) { continue }
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        if ($manifest.id -notin $ids) { continue }
        if ($folderSources.ContainsKey($manifest.id)) { throw "Duplicate installed ID: $($manifest.id)" }
        $folderSources[$manifest.id] = $folder.FullName
    }
    foreach ($id in $ids) {
        if (!$folderSources.ContainsKey($id)) { throw "Missing installed folder: $id" }
    }
} elseif ($InstalledModsDirectory) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zipRoot = (Resolve-Path -LiteralPath $InstalledModsDirectory).Path
    foreach ($archive in Get-ChildItem -LiteralPath $zipRoot -File -Filter '*.zip') {
        $zip = [IO.Compression.ZipFile]::OpenRead($archive.FullName)
        try {
            $manifestEntries = @($zip.Entries | Where-Object { $_.FullName -match '^([^/]+/)?mod.json$' })
            if ($manifestEntries.Count -ne 1) { throw "Ambiguous manifest in $($archive.Name)" }
            $reader = [IO.StreamReader]::new($manifestEntries[0].Open())
            try { $manifest = $reader.ReadToEnd() | ConvertFrom-Json } finally { $reader.Dispose() }
            if (!$IncludeOtherMods -and $manifest.id -notin $ids) { continue }
            if ($zipSources.ContainsKey($manifest.id)) { throw "Duplicate installed ID: $($manifest.id)" }
            $zipSources[$manifest.id] = $archive.FullName
            $installations += @{ id=$manifest.id; version=$manifest.version; archive=$archive.Name; location='user://mods'; format='zip'; sha256=(Get-FileHash -LiteralPath $archive.FullName).Hash.ToLowerInvariant() }
        } finally { $zip.Dispose() }
    }
    foreach ($id in $ids) { if (!$zipSources.ContainsKey($id)) { throw "Missing installed ZIP: $id" } }
} else {
    foreach ($id in $ids) {
        $manifest = Get-Content -LiteralPath (Join-Path $workspace "mods/$id/mod.json") -Raw | ConvertFrom-Json
        $package = Join-Path $workspace ("dist/$id/$id-" + $manifest.version + '.zip')
        if (!(Test-Path -LiteralPath $package)) { throw "Build package first: $package" }
        $packages += Split-Path -Leaf $package
        Copy-Item -LiteralPath $package -Destination (Join-Path $qa 'mods') -Force
    }
}
$extra = Get-ChildItem -LiteralPath (Join-Path $qa 'mods') -Force | Where-Object { $_.Name -notin $packages }
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
$copiedFolders = $false
try {
    if ($FolderModsDirectory -or $InstalledModsDirectory) {
        New-Item -ItemType Directory -Path $profileMods | Out-Null
        $copiedFolders = $true
        foreach ($id in $folderSources.Keys) {
            $source = $folderSources[$id]
            $name = Split-Path -Leaf $source
            Copy-Item -LiteralPath $source -Destination (Join-Path $profileMods $name) -Recurse
            $installations += @{ id = $id; folder = $name; location = 'user://mods'; format = 'folder' }
        }
        foreach ($source in $zipSources.Values) { Copy-Item -LiteralPath $source -Destination (Join-Path $profileMods ([IO.Path]::GetFileName($source))) }
        $installations | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $output 'installations.json') -Encoding utf8
    }
    if (!(Test-Path -LiteralPath $license)) {
        if (!$UseLocalLicense) { throw 'QA needs a valid license. Use -UseLocalLicense to copy your existing local license on this computer; it is removed afterward.' }
        Copy-Item -LiteralPath (Join-Path $env:APPDATA 'Pax Universe/license.json') -Destination $license
        $copiedLicense = $true
    }
    $modSelection = if ($Stage -eq 'nativeextras') { '{"disabled":["pax_interface"],"order":["earth_atlas","pax_interface"],"seen":["earth_atlas","pax_interface"]}' } else { '{"disabled":[],"order":["earth_atlas","pax_interface"],"seen":["earth_atlas","pax_interface"]}' }
    [IO.File]::WriteAllText((Join-Path $profile 'mods.json'), $modSelection)
    [IO.File]::WriteAllText((Join-Path $profile 'settings.json'), '{"язык":"ru","заставка":false,"провайдеры":{"мозг":{"режим":"выкл"}}}')
    $env:PAX_COMPAT_OUTPUT = $output
    $env:PAX_UI_TEST_OUTPUT = $output
    $env:PAX_COMPAT_STAGE = $Stage
    $launchArguments = @('--resolution','1920x1080','--quit-after','30000')
    if ($VerboseEngine) { $launchArguments += '--verbose' }
    if ($Headless) { $launchArguments += '--headless' }
    $process = Start-Process -FilePath (Join-Path $qa 'PaxUniverse.exe') -WorkingDirectory $qa -WindowStyle Hidden -PassThru -ArgumentList $launchArguments -RedirectStandardOutput (Join-Path $output 'runtime.out.log') -RedirectStandardError (Join-Path $output 'runtime.err.log')
    if (!$process.WaitForExit(600000)) {
        Stop-Process -Id $process.Id
        throw 'QA timed out; logs are retained.'
    }
    $process.Refresh()
    @{ exit_code=$process.ExitCode; stage=$Stage; headless=[bool]$Headless; has_exited=$process.HasExited } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $output 'process-result.json') -Encoding utf8
    $report = Get-Content -LiteralPath (Join-Path $output 'compatibility-report.json') -Raw | ConvertFrom-Json
    if ($process.ExitCode -ne 0 -or !$report.ok) { throw "Compatibility check failed (exit=$($process.ExitCode), report.ok=$($report.ok)). Read $output" }
    if ($report.stage -ne $Stage) { throw "Report stage does not match requested stage: $Stage" }
    $completionChecks = @{
        atlas=@{ report='atlas'; check='atlas_functional_tests' }
        reload=@{ report='reload'; check='reload_functional_tests' }
        coexist=@{ report='coexist'; check='store_coexist_tests' }
        nativeextras=@{ report='native_control'; check='native_control_completed' }
    }
    $requiredNestedReports = @()
    if ($completionChecks.ContainsKey($Stage)) { $requiredNestedReports += $completionChecks[$Stage] }
    if ($Stage -eq 'interface') {
        $requiredNestedReports += @{ report='optional_window_bindings'; check='optional_window_bindings' }
        $requiredNestedReports += @{ report='native_content_rebuild'; check='native_content_rebuild' }
    }
    foreach ($spec in $requiredNestedReports) {
        $reportKey = $spec.report
        $completionKey = $spec.check
        $stageReport = $report.$reportKey
        $assertions = @($stageReport.checks.PSObject.Properties)
        $failedAssertions = @($assertions | Where-Object { $_.Value -isnot [bool] -or $_.Value -ne $true })
        if ($stageReport.ok -isnot [bool] -or $stageReport.ok -ne $true -or
            $report.checks.$completionKey -isnot [bool] -or $report.checks.$completionKey -ne $true -or
            $assertions.Count -lt 1 -or $failedAssertions.Count -gt 0 -or
            $null -eq $stageReport.failures -or @($stageReport.failures).Count -gt 0) {
            throw "Missing, incomplete or failed final nested report: $reportKey ($Stage)"
        }
    }
    if ($Stage -eq 'interface') {
        $interfaceReport = Get-Content -LiteralPath (Join-Path $output 'live-test-report.json') -Raw | ConvertFrom-Json
        if ($interfaceReport.ok -isnot [bool] -or $interfaceReport.ok -ne $true -or $interfaceReport.assertion_count -lt 500) { throw 'Incomplete or failed HUD checks.' }
    }
    $errors = Get-Content -LiteralPath (Join-Path $output 'runtime.err.log') -Raw
    if ($errors -match '(?m)^ERROR:|SCRIPT ERROR|Parse Error|COMPAT_FAIL') { throw "Runtime errors. Read $output" }
    Write-Output ("PASS $Stage; game=" + $report.version + "; reports=$output")
} finally {
    foreach ($path in $backups.Keys) {
        if ($null -ne $backups[$path]) { [IO.File]::WriteAllBytes($path, $backups[$path]) }
        elseif (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path }
    }
    if ($copiedLicense -and (Test-Path -LiteralPath $license)) { Remove-Item -LiteralPath $license }
    if ($copiedFolders -and (Test-Path -LiteralPath $profileMods)) {
        # Only the temporary directory created above may be removed, never source installations.
        $resolvedMods = (Resolve-Path -LiteralPath $profileMods).Path
        $expectedMods = [IO.Path]::GetFullPath((Join-Path $env:APPDATA 'Pax Universe Atlas QA/mods'))
        if ($resolvedMods -ne $expectedMods -or ($FolderModsDirectory -and $resolvedMods -eq $folderRoot) -or ($InstalledModsDirectory -and $resolvedMods -eq $zipRoot)) {
            throw 'Unexpected QA mods path; temporary copies preserved.'
        }
        Remove-Item -LiteralPath $resolvedMods -Recurse
    }
}
