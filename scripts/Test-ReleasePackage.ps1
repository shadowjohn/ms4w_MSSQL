[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$PackagePath,

    [Parameter(Mandatory)]
    [string]$ChecksumPath,

    [Parameter(Mandatory)]
    [string]$ManifestPath,

    [switch]$KeepExtracted
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$resolvedPackage = (Resolve-Path -LiteralPath $PackagePath).Path
$resolvedChecksum = (Resolve-Path -LiteralPath $ChecksumPath).Path
$resolvedManifest = (Resolve-Path -LiteralPath $ManifestPath).Path
$packageFile = Get-Item -LiteralPath $resolvedPackage
$packageBaseName = [System.IO.Path]::GetFileNameWithoutExtension($packageFile.Name)
$expectedRootPrefix = "$packageBaseName/"

$checksums = @{}
foreach ($line in Get-Content -LiteralPath $resolvedChecksum -Encoding UTF8) {
    if (-not $line.Trim()) {
        continue
    }
    if ($line -notmatch '^([0-9a-fA-F]{64})\s{2}(.+)$') {
        throw "SHA256SUMS.txt 格式不符：$line"
    }
    $checksums[$Matches[2]] = $Matches[1].ToLowerInvariant()
}

foreach ($assetPath in @($resolvedPackage, $resolvedManifest)) {
    $assetName = Split-Path -Leaf $assetPath
    if (-not $checksums.ContainsKey($assetName)) {
        throw "SHA256SUMS.txt 缺少 $assetName。"
    }
    $actualHash = (Get-FileHash -LiteralPath $assetPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualHash -ne $checksums[$assetName]) {
        throw "$assetName 的 SHA-256 不符。"
    }
}

$archiveEntries = @(& tar.exe -tf $resolvedPackage)
if ($LASTEXITCODE -ne 0 -or $archiveEntries.Count -eq 0) {
    throw '無法讀取 ZIP 內容。'
}

foreach ($entry in $archiveEntries) {
    if ($entry -match '^[\\/]' -or $entry -match '^[A-Za-z]:' -or ($entry -split '/') -contains '..') {
        throw "ZIP 含有不安全路徑：$entry"
    }
    if (-not $entry.StartsWith($expectedRootPrefix, [StringComparison]::Ordinal)) {
        throw "ZIP 不是單一根目錄結構：$entry"
    }
    if ($entry -match '/tmp/https%3A' -or $entry -match '/tmp/ms_tmp/[^/]+\.png$') {
        throw "ZIP 不應包含 runtime cache：$entry"
    }
}

$requiredEntries = @(
    "${expectedRootPrefix}README.md",
    "${expectedRootPrefix}LICENSE",
    "${expectedRootPrefix}apache-install.bat",
    "${expectedRootPrefix}ms4w_MSSQL/VERSION.txt",
    "${expectedRootPrefix}ms4w_MSSQL/Apache/bin/httpd.exe"
)
foreach ($requiredEntry in $requiredEntries) {
    if ($archiveEntries -notcontains $requiredEntry) {
        throw "ZIP 缺少必要項目：$requiredEntry"
    }
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) "ms4w-release-test-$PID-$([guid]::NewGuid().ToString('N'))"
$expectedTempPrefix = [System.IO.Path]::GetFullPath((Join-Path ([System.IO.Path]::GetTempPath()) 'ms4w-release-test-'))
$resolvedTempRoot = [System.IO.Path]::GetFullPath($tempRoot)
if (-not $resolvedTempRoot.StartsWith($expectedTempPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw "暫存目錄不在預期位置：$resolvedTempRoot"
}

try {
    New-Item -ItemType Directory -Path $resolvedTempRoot | Out-Null
    & tar.exe -xf $resolvedPackage -C $resolvedTempRoot
    if ($LASTEXITCODE -ne 0) {
        throw 'ZIP 解壓縮失敗。'
    }

    $extractedRoot = Join-Path $resolvedTempRoot $packageBaseName
    & (Join-Path $PSScriptRoot 'Test-Runtime.ps1') -RootPath $extractedRoot
    if ($LASTEXITCODE -ne 0) {
        throw '解壓後 runtime smoke check 失敗。'
    }

    $manifest = Get-Content -LiteralPath $resolvedManifest -Encoding UTF8 -Raw | ConvertFrom-Json
    if ($manifest.artifact.fileName -ne $packageFile.Name) {
        throw 'release-manifest.json 的檔名不符。'
    }
    if ($manifest.artifact.sha256 -ne $checksums[$packageFile.Name]) {
        throw 'release-manifest.json 的 ZIP SHA-256 不符。'
    }

    Write-Host "Release package smoke check passed: $($archiveEntries.Count) entries"
    Write-Host "Extracted root: $packageBaseName"
}
finally {
    if ($KeepExtracted -and (Test-Path -LiteralPath $resolvedTempRoot)) {
        Write-Host "Kept extracted package for inspection: $resolvedTempRoot"
    }
    elseif (Test-Path -LiteralPath $resolvedTempRoot) {
        [System.IO.Directory]::Delete($resolvedTempRoot, $true)
    }
}
