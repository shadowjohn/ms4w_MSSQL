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

$excludedReleasePaths = @(
    'ms4w_MSSQL/Apache/bin/.rnd',
    'ms4w_MSSQL/Apache/htdocs/test_geo.php',
    'ms4w_MSSQL/Apache/htdocs/test_pdo_geo.php',
    'ms4w_MSSQL/Apache/htdocs/old/phpinfo.php',
    'ms4w_MSSQL/Apache/htdocs/old/phpinfo_mapscript.php',
    'ms4w_MSSQL/Apache/htdocs/old/phpinfo_php_ogr.php',
    'ms4w_MSSQL/Apache/cgi-bin/printenv.pl',
    'ms4w_MSSQL/Apache/cgi-bin/test.png'
)

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
    if ($entry -match '^[\\/]' -or $entry -match ':' -or ($entry -split '[\\/]') -contains '..') {
        throw "ZIP 含有不安全路徑：$entry"
    }
    if (-not $entry.StartsWith($expectedRootPrefix, [StringComparison]::Ordinal)) {
        throw "ZIP 不是單一根目錄結構：$entry"
    }
    if ($entry -match '/tmp/https%3A' -or $entry -match '/tmp/ms_tmp/[^/]+\.png$') {
        throw "ZIP 不應包含 runtime cache：$entry"
    }
    $relativeEntry = $entry.Substring($expectedRootPrefix.Length).Replace('\', '/')
    if ($excludedReleasePaths -contains $relativeEntry) {
        throw "ZIP contains an excluded demo or runtime state file: $entry"
    }
}

$requiredEntries = @(
    "${expectedRootPrefix}README.md",
    "${expectedRootPrefix}LICENSE",
    "${expectedRootPrefix}apache-install.bat",
    "${expectedRootPrefix}ms4w_MSSQL/VERSION.txt",
    "${expectedRootPrefix}ms4w_MSSQL/Apache/bin/httpd.exe",
    "${expectedRootPrefix}ms4w_MSSQL/PHP_RUNTIME.json",
    "${expectedRootPrefix}ms4w_MSSQL/APACHE_RUNTIME.json"
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
    $runtimeRoot = [System.IO.Path]::GetFullPath((Join-Path $extractedRoot 'ms4w_MSSQL'))
    $runtimePrefix = $runtimeRoot.TrimEnd([char[]]'\/') + [System.IO.Path]::DirectorySeparatorChar
    foreach ($payloadManifestName in @('PHP_RUNTIME.json', 'APACHE_RUNTIME.json')) {
        $payloadManifestPath = Join-Path $runtimeRoot $payloadManifestName
        $payloadManifest = Get-Content -LiteralPath $payloadManifestPath -Encoding UTF8 -Raw | ConvertFrom-Json
        $payloadFiles = @($payloadManifest.files)
        if ($payloadManifest.schemaVersion -ne 1 -or $payloadFiles.Count -eq 0) {
            throw "Invalid or empty runtime payload manifest: $payloadManifestName"
        }

        foreach ($payloadFile in $payloadFiles) {
            $relativePath = [string]$payloadFile.path
            if ([string]::IsNullOrWhiteSpace($relativePath) -or
                [System.IO.Path]::IsPathRooted($relativePath) -or $relativePath -match ':' -or
                ($relativePath -split '[\\/]') -contains '..') {
                throw "Unsafe payload manifest path in ${payloadManifestName}: $relativePath"
            }
            $payloadPath = [System.IO.Path]::GetFullPath((Join-Path $runtimeRoot ($relativePath -replace '/', '\')))
            if (-not $payloadPath.StartsWith($runtimePrefix, [StringComparison]::OrdinalIgnoreCase)) {
                throw "Payload manifest path escapes the runtime directory: $relativePath"
            }
            if (-not (Test-Path -LiteralPath $payloadPath -PathType Leaf)) {
                throw "Missing runtime payload file from ${payloadManifestName}: $relativePath"
            }
            if ($payloadFile.sha256 -notmatch '^[0-9a-fA-F]{64}$') {
                throw "Invalid payload SHA-256 in ${payloadManifestName}: $relativePath"
            }
            $actualHash = (Get-FileHash -LiteralPath $payloadPath -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($actualHash -ne $payloadFile.sha256) {
                throw "Runtime payload SHA-256 mismatch in ${payloadManifestName}: $relativePath"
            }
        }
    }

    $runtimeReportJson = & (Join-Path $PSScriptRoot 'Test-Runtime.ps1') -RootPath $extractedRoot -AsJson
    if ($LASTEXITCODE -ne 0) {
        throw '解壓後 runtime smoke check 失敗。'
    }
    $runtimeReport = $runtimeReportJson | ConvertFrom-Json

    $manifest = Get-Content -LiteralPath $resolvedManifest -Encoding UTF8 -Raw | ConvertFrom-Json
    if ($manifest.artifact.fileName -ne $packageFile.Name) {
        throw 'release-manifest.json 的檔名不符。'
    }
    if ($manifest.artifact.sha256 -ne $checksums[$packageFile.Name]) {
        throw 'release-manifest.json 的 ZIP SHA-256 不符。'
    }
    if ($manifest.artifact.bytes -ne $packageFile.Length -or $manifest.bundleVersion -ne $runtimeReport.bundleVersion) {
        throw 'release-manifest.json artifact size or bundle version does not match the package.'
    }

    $checkedExecutables = @{}
    foreach ($executable in @($runtimeReport.executables)) {
        $checkedExecutables[$executable.path] = $executable
    }
    $manifestExecutables = @($manifest.keyExecutables)
    if ($manifestExecutables.Count -ne $checkedExecutables.Count) {
        throw 'release-manifest.json key executable count does not match the extracted runtime report.'
    }
    $seenExecutablePaths = @{}
    foreach ($executable in $manifestExecutables) {
        if (-not $checkedExecutables.ContainsKey($executable.path) -or $seenExecutablePaths.ContainsKey($executable.path)) {
            throw "Unexpected or duplicate key executable path in release-manifest.json: $($executable.path)"
        }
        $seenExecutablePaths[$executable.path] = $true
        $actualExecutable = $checkedExecutables[$executable.path]
        if ($executable.sha256 -ne $actualExecutable.sha256 -or $executable.bytes -ne $actualExecutable.bytes) {
            throw "Key executable SHA-256 or size mismatch: $($executable.path)"
        }
    }

    Write-Host "Release package smoke check passed: $($archiveEntries.Count) entries"
    Write-Host "Extracted root: $packageBaseName"
}
finally {
    if ($KeepExtracted -and (Test-Path -LiteralPath $resolvedTempRoot)) {
        Write-Host "Kept extracted package for inspection: $resolvedTempRoot"
    }
    elseif (Test-Path -LiteralPath $resolvedTempRoot) {
        $cleanupRoot = (Resolve-Path -LiteralPath $resolvedTempRoot).Path
        if ($cleanupRoot -ne $resolvedTempRoot -or
            -not $cleanupRoot.StartsWith($expectedTempPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to delete an unexpected package test temp path: $cleanupRoot"
        }
        Remove-Item -LiteralPath $cleanupRoot -Recurse -Force
    }
}
