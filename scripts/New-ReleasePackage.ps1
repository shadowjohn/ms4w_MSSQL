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
    ':(exclude,glob)ms4w_MSSQL/tmp/ms_tmp/*.png',
    ':(exclude,literal)ms4w_MSSQL/Apache/bin/.rnd',
    ':(exclude,literal)ms4w_MSSQL/Apache/htdocs/test_geo.php',
    ':(exclude,literal)ms4w_MSSQL/Apache/htdocs/test_pdo_geo.php',
    ':(exclude,literal)ms4w_MSSQL/Apache/htdocs/old/phpinfo.php',
    ':(exclude,literal)ms4w_MSSQL/Apache/htdocs/old/phpinfo_mapscript.php',
    ':(exclude,literal)ms4w_MSSQL/Apache/htdocs/old/phpinfo_php_ogr.php',
    ':(exclude,literal)ms4w_MSSQL/Apache/cgi-bin/printenv.pl',
    ':(exclude,literal)ms4w_MSSQL/Apache/cgi-bin/test.png'
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

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) "ms4w-release-build-$PID-$([guid]::NewGuid().ToString('N'))"
$expectedTempPrefix = [System.IO.Path]::GetFullPath((Join-Path ([System.IO.Path]::GetTempPath()) 'ms4w-release-build-'))
$resolvedTempRoot = [System.IO.Path]::GetFullPath($tempRoot)
if (-not $resolvedTempRoot.StartsWith($expectedTempPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Release snapshot temp path is outside the expected location: $resolvedTempRoot"
}

try {
    New-Item -ItemType Directory -Path $resolvedTempRoot | Out-Null
    & tar.exe -xf $packagePath -C $resolvedTempRoot
    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to extract the HEAD release snapshot.'
    }

    $snapshotRoot = Join-Path $resolvedTempRoot $packageBaseName
    $runtimeReportJson = & (Join-Path $PSScriptRoot 'Test-Runtime.ps1') -RootPath $snapshotRoot -AsJson
    if ($LASTEXITCODE -ne 0) {
        throw 'HEAD snapshot runtime smoke check failed.'
    }
    $runtimeReport = $runtimeReportJson | ConvertFrom-Json
}
finally {
    if (Test-Path -LiteralPath $resolvedTempRoot) {
        $cleanupRoot = (Resolve-Path -LiteralPath $resolvedTempRoot).Path
        if ($cleanupRoot -ne $resolvedTempRoot -or
            -not $cleanupRoot.StartsWith($expectedTempPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to delete an unexpected snapshot temp path: $cleanupRoot"
        }
        Remove-Item -LiteralPath $cleanupRoot -Recurse -Force
    }
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
