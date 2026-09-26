param([string]$GameDirectory = (Join-Path $env:LOCALAPPDATA 'Programs/Pax Universe'))
$ErrorActionPreference = 'Stop'
$workspace = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$original = (Resolve-Path -LiteralPath $GameDirectory).Path
$root = Join-Path $workspace '.local/Pax Universe Refactor'
$manifest = Get-Content -LiteralPath (Join-Path $root 'original-inventory.json') -Raw | ConvertFrom-Json
$differences = @()
foreach ($entry in $manifest.files) {
    $path = [IO.Path]::GetFullPath((Join-Path $original $entry.path))
    if (!$path.StartsWith($original.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe inventory path' }
    if (!(Test-Path -LiteralPath $path -PathType Leaf)) { $differences += @{path=$entry.path; reason='missing'}; continue }
    $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($hash -ne $entry.sha256) { $differences += @{path=$entry.path; reason='hash_changed'} }
}
$report = @{ checked_utc=[DateTime]::UtcNow.ToString('o'); checked_files=$manifest.files.Count; changed_files=@($differences); ok=($differences.Count -eq 0); method='SHA-256 of every file captured before the experiment' }
$report | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $root 'original-verification.json') -Encoding utf8
$report | ConvertTo-Json -Depth 5
if (!$report.ok) { throw 'Original installation differs from the recorded control; no files were restored or overwritten.' }
