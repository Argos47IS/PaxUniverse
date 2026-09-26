param([string]$GameDirectory = (Join-Path $env:LOCALAPPDATA 'Programs/Pax Universe'))
$ErrorActionPreference = 'Stop'
$workspace = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$source = (Resolve-Path -LiteralPath $GameDirectory).Path
$root = Join-Path $workspace '.local/Pax Universe Refactor'
$target = Join-Path $workspace '.local/refactor-game'
if ((Test-Path -LiteralPath $target) -and (Get-ChildItem -LiteralPath $target -File -Recurse -Force)) { throw 'Experiment already exists; do not overwrite the baseline.' }
New-Item -ItemType Directory -Path $target -Force | Out-Null
$inventory = @()
foreach ($file in Get-ChildItem -LiteralPath $source -File -Recurse -Force) {
    $relative = [IO.Path]::GetRelativePath($source, $file.FullName)
    $destination = Join-Path $target $relative
    New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
    # Stream contents into a new file: never make links to the control installation.
    $inputStream = [IO.File]::OpenRead($file.FullName)
    try {
        $outputStream = [IO.File]::Open($destination, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write)
        try { $inputStream.CopyTo($outputStream) } finally { $outputStream.Dispose() }
    } finally { $inputStream.Dispose() }
    $originalHash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
    $copyHash = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash
    if ($originalHash -ne $copyHash) { throw "Copy verification failed: $relative" }
    $inventory += @{ path = $relative.Replace('\','/'); bytes = $file.Length; sha256 = $originalHash.ToLowerInvariant() }
}
$metadata = @{ created_utc = [DateTime]::UtcNow.ToString('o'); files = $inventory; count = $inventory.Count; bytes = ($inventory | Measure-Object bytes -Sum).Sum; independent_copy = $true }
$metadata | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $root 'original-inventory.json') -Encoding utf8
Write-Output "Verified independent copy: $target; $($inventory.Count) files; $($metadata.bytes) bytes"
