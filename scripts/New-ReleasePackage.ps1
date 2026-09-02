[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^v[0-9A-Za-z][0-9A-Za-z._-]*$')]
    [string]$ReleaseTag,

    [string]$OutputDirectory = (Join-Path (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path 'artifacts')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (& git -C (Join-Path $PSScriptRoot '..') rev-parse --show-toplevel).Trim()
if ($LASTEXITCODE -ne 0 -or -not $repoRoot) {
    throw '找不到 Git repository 根目錄。'
}
$repoRoot = (Resolve-Path -LiteralPath $repoRoot).Path

$sourceCommit = (& git -C $repoRoot rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $sourceCommit -notmatch '^[0-9a-f]{40}$') {
    throw '無法取得目前 commit。'
}

$runtimeReportJson = & (Join-Path $PSScriptRoot 'Test-Runtime.ps1') -RootPath $repoRoot -AsJson
if ($LASTEXITCODE -ne 0) {
    throw 'Runtime smoke check 失敗。'
}
$runtimeReport = $runtimeReportJson | ConvertFrom-Json

if (-not (Test-Path -LiteralPath $OutputDirectory)) {
    New-Item -ItemType Directory -Path $OutputDirectory | Out-Null
}
$resolvedOutput = (Resolve-Path -LiteralPath $OutputDirectory).Path

$packageBaseName = "ms4w_MSSQL-$ReleaseTag-windows-x64"
$packagePath = Join-Path $resolvedOutput "$packageBaseName.zip"
$manifestPath = Join-Path $resolvedOutput 'release-manifest.json'
$checksumPath = Join-Path $resolvedOutput 'SHA256SUMS.txt'

foreach ($outputPath in @($packagePath, $manifestPath, $checksumPath)) {
    if (Test-Path -LiteralPath $outputPath) {
        [System.IO.File]::Delete((Resolve-Path -LiteralPath $outputPath).Path)
    }
}

$archivePaths = @(
    'README.md',
    'LICENSE',
    'apache-install.bat',
    'apache-restart.bat',
    'apache-uninstall.bat',
    'ms4w_MSSQL',
    ':(exclude,glob)ms4w_MSSQL/tmp/https%3A*',
    ':(exclude,glob)ms4w_MSSQL/tmp/ms_tmp/*.png'
)

$gitArguments = @(
    '-C', $repoRoot,
    'archive',
    '--format=zip',
    "--prefix=$packageBaseName/",
    "--output=$packagePath",
    $sourceCommit,
    '--'
) + $archivePaths

& git @gitArguments
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $packagePath -PathType Leaf)) {
    throw '建立 Release ZIP 失敗。'
}

$archiveHash = (Get-FileHash -LiteralPath $packagePath -Algorithm SHA256).Hash.ToLowerInvariant()
$archiveFile = Get-Item -LiteralPath $packagePath
$excludedCacheFiles = @(git -C $repoRoot ls-files -- 'ms4w_MSSQL/tmp/https%3A*' 'ms4w_MSSQL/tmp/ms_tmp/*.png')
if ($LASTEXITCODE -ne 0) {
    throw '無法計算排除的 cache 檔案。'
}

$manifest = [ordered]@{
    schemaVersion = 1
    releaseTag = $ReleaseTag
    sourceCommit = $sourceCommit
    bundleVersion = $runtimeReport.bundleVersion
    artifact = [ordered]@{
        fileName = $archiveFile.Name
        bytes = $archiveFile.Length
        sha256 = $archiveHash
    }
    packaging = [ordered]@{
        source = 'git archive'
        excludedRuntimeCacheFiles = $excludedCacheFiles.Count
    }
    vcRuntime = $runtimeReport.vcRuntime
    keyExecutables = $runtimeReport.executables
}

$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText(
    $manifestPath,
    (($manifest | ConvertTo-Json -Depth 8) + "`n"),
    $utf8NoBom
)

$manifestHash = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
$checksumLines = @(
    "$archiveHash  $($archiveFile.Name)",
    "$manifestHash  $(Split-Path -Leaf $manifestPath)"
)
[System.IO.File]::WriteAllText($checksumPath, (($checksumLines -join "`n") + "`n"), $utf8NoBom)

Write-Host "Release package created: $packagePath"
Write-Host "Package bytes: $($archiveFile.Length)"
Write-Host "Package SHA-256: $archiveHash"
Write-Host "Excluded runtime cache files: $($excludedCacheFiles.Count)"

[pscustomobject]@{
    PackagePath = $packagePath
    ManifestPath = $manifestPath
    ChecksumPath = $checksumPath
    Sha256 = $archiveHash
    Bytes = $archiveFile.Length
}
