[CmdletBinding()]
param(
    [string]$RootPath = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path,
    [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$resolvedRoot = (Resolve-Path -LiteralPath $RootPath).Path

$requiredFiles = @(
    'README.md',
    'LICENSE',
    'apache-install.bat',
    'apache-restart.bat',
    'apache-uninstall.bat',
    'ms4w_MSSQL\VERSION.txt',
    'ms4w_MSSQL\LICENSE.txt'
)

foreach ($relativePath in $requiredFiles) {
    $fullPath = Join-Path $resolvedRoot $relativePath
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        throw "缺少必要檔案：$relativePath"
    }
}

$bundleVersion = (Get-Content -LiteralPath (Join-Path $resolvedRoot 'ms4w_MSSQL\VERSION.txt') -Encoding UTF8 -Raw).Trim()
if ($bundleVersion -notmatch '^MS4W\s+\d+\.\d+\.\d+$') {
    throw "VERSION.txt 格式不符：$bundleVersion"
}

function Invoke-VersionCheck {
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$RelativePath,

        [Parameter(Mandatory)]
        [string[]]$ArgumentList,

        [Parameter(Mandatory)]
        [string]$ExpectedPattern
    )

    $executablePath = Join-Path $resolvedRoot $RelativePath
    if (-not (Test-Path -LiteralPath $executablePath -PathType Leaf)) {
        throw "找不到 $Name：$RelativePath"
    }

    $outputLines = @(& $executablePath @ArgumentList 2>&1 | ForEach-Object { $_.ToString() })
    $exitCode = $LASTEXITCODE
    $output = ($outputLines -join "`n").Trim()

    if ($exitCode -ne 0) {
        throw "$Name 執行失敗（exit code $exitCode）：$output"
    }

    if ($output -notmatch $ExpectedPattern) {
        throw "$Name 版本輸出不符預期：$output"
    }

    $file = Get-Item -LiteralPath $executablePath
    $signature = Get-AuthenticodeSignature -LiteralPath $executablePath

    [pscustomobject][ordered]@{
        name = $Name
        path = $RelativePath.Replace('\', '/')
        versionOutput = $output
        bytes = $file.Length
        sha256 = (Get-FileHash -LiteralPath $executablePath -Algorithm SHA256).Hash.ToLowerInvariant()
        authenticodeStatus = $signature.Status.ToString()
        signer = if ($signature.SignerCertificate) { $signature.SignerCertificate.Subject } else { $null }
    }
}

$checks = @(
    @{
        Name = 'Apache'
        RelativePath = 'ms4w_MSSQL\Apache\bin\httpd.exe'
        ArgumentList = @('-v')
        ExpectedPattern = 'Apache/2\.4\.68'
    },
    @{
        Name = 'PHP'
        RelativePath = 'ms4w_MSSQL\Apache\php\php.exe'
        ArgumentList = @('-v')
        ExpectedPattern = 'PHP 8\.3\.32'
    },
    @{
        Name = 'GDAL'
        RelativePath = 'ms4w_MSSQL\GDAL\gdalinfo.exe'
        ArgumentList = @('--version')
        ExpectedPattern = 'GDAL 2\.4\.0'
    },
    @{
        Name = 'Python'
        RelativePath = 'ms4w_MSSQL\python\python.exe'
        ArgumentList = @('--version')
        ExpectedPattern = 'Python 3\.7\.8'
    },
    @{
        Name = 'SQLite'
        RelativePath = 'ms4w_MSSQL\sqlite3_ext\sqlite3.exe'
        ArgumentList = @('--version')
        ExpectedPattern = '^3\.42\.0'
    },
    @{
        Name = 'MapServer'
        RelativePath = 'ms4w_MSSQL\Apache\cgi-bin\mapserv.exe'
        ArgumentList = @('-v')
        ExpectedPattern = 'MapServer version 7\.7\.0-dev'
    }
)

$executables = @($checks | ForEach-Object { Invoke-VersionCheck @_ })
$result = [pscustomobject][ordered]@{
    bundleVersion = $bundleVersion
    rootPath = $resolvedRoot
    checkedAtUtc = [DateTimeOffset]::UtcNow.ToString('o')
    executables = $executables
}

if ($AsJson) {
    $result | ConvertTo-Json -Depth 6
    return
}

Write-Host "Runtime smoke check passed: $($executables.Count)/$($executables.Count)"
Write-Host "Bundle: $bundleVersion"
foreach ($executable in $executables) {
    $firstLine = ($executable.versionOutput -split "`n")[0]
    Write-Host "- $($executable.name): $firstLine [$($executable.authenticodeStatus)]"
}
