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

function Convert-RvaToFileOffset {
    param(
        [Parameter(Mandatory)]
        [uint32]$Rva,

        [Parameter(Mandatory)]
        [object[]]$Sections
    )

    foreach ($section in $Sections) {
        $start = [uint64]$section.VirtualAddress
        $end = $start + [uint64]$section.Span
        if ([uint64]$Rva -ge $start -and [uint64]$Rva -lt $end) {
            return [int]([uint64]$section.RawOffset + ([uint64]$Rva - $start))
        }
    }

    throw ('PE import RVA 無法對應檔案位置：0x{0:X8}' -f $Rva)
}

function Get-PeImportedDllNames {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -lt 0x40 -or $bytes[0] -ne 0x4D -or $bytes[1] -ne 0x5A) {
        throw "不是有效的 PE 檔案：$Path"
    }

    $peOffset = [int][BitConverter]::ToUInt32($bytes, 0x3C)
    if ($peOffset -lt 0 -or $peOffset + 24 -gt $bytes.Length -or
        [Text.Encoding]::ASCII.GetString($bytes, $peOffset, 4) -ne "PE`0`0") {
        throw "PE header 格式不符：$Path"
    }

    $sectionCount = [int][BitConverter]::ToUInt16($bytes, $peOffset + 6)
    $optionalHeaderSize = [int][BitConverter]::ToUInt16($bytes, $peOffset + 20)
    $optionalHeaderOffset = $peOffset + 24
    $optionalHeaderMagic = [BitConverter]::ToUInt16($bytes, $optionalHeaderOffset)
    $dataDirectoryOffset = switch ($optionalHeaderMagic) {
        0x20B { $optionalHeaderOffset + 112; break }
        0x10B { $optionalHeaderOffset + 96; break }
        default { throw "不支援的 PE optional header：0x$('{0:X4}' -f $optionalHeaderMagic) ($Path)" }
    }

    $importRva = [BitConverter]::ToUInt32($bytes, $dataDirectoryOffset + 8)
    if ($importRva -eq 0) {
        return @()
    }

    $sectionOffset = $optionalHeaderOffset + $optionalHeaderSize
    if ($sectionOffset + ($sectionCount * 40) -gt $bytes.Length) {
        throw "PE section table 超出檔案範圍：$Path"
    }

    $sections = @(
        for ($index = 0; $index -lt $sectionCount; $index++) {
            $offset = $sectionOffset + ($index * 40)
            $virtualSize = [BitConverter]::ToUInt32($bytes, $offset + 8)
            $virtualAddress = [BitConverter]::ToUInt32($bytes, $offset + 12)
            $rawSize = [BitConverter]::ToUInt32($bytes, $offset + 16)
            $rawOffset = [BitConverter]::ToUInt32($bytes, $offset + 20)
            [pscustomobject]@{
                VirtualAddress = $virtualAddress
                Span = [Math]::Max([uint64]$virtualSize, [uint64]$rawSize)
                RawOffset = $rawOffset
            }
        }
    )

    $descriptorOffset = Convert-RvaToFileOffset -Rva $importRva -Sections $sections
    $imports = [System.Collections.Generic.List[string]]::new()
    while ($descriptorOffset + 20 -le $bytes.Length) {
        $originalFirstThunk = [BitConverter]::ToUInt32($bytes, $descriptorOffset)
        $nameRva = [BitConverter]::ToUInt32($bytes, $descriptorOffset + 12)
        $firstThunk = [BitConverter]::ToUInt32($bytes, $descriptorOffset + 16)
        if ($originalFirstThunk -eq 0 -and $nameRva -eq 0 -and $firstThunk -eq 0) {
            break
        }

        $nameOffset = Convert-RvaToFileOffset -Rva $nameRva -Sections $sections
        $endOffset = $nameOffset
        while ($endOffset -lt $bytes.Length -and $bytes[$endOffset] -ne 0) {
            $endOffset++
        }
        if ($endOffset -ge $bytes.Length) {
            throw "PE import 名稱未以 NUL 結尾：$Path"
        }

        $imports.Add([Text.Encoding]::ASCII.GetString($bytes, $nameOffset, $endOffset - $nameOffset))
        $descriptorOffset += 20
    }

    return $imports.ToArray()
}

function Get-PeArchitecture {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -lt 0x40 -or $bytes[0] -ne 0x4D -or $bytes[1] -ne 0x5A) {
        throw "不是有效的 PE 檔案：$Path"
    }

    $peOffset = [int][BitConverter]::ToUInt32($bytes, 0x3C)
    if ($peOffset -lt 0 -or $peOffset + 6 -gt $bytes.Length -or
        [Text.Encoding]::ASCII.GetString($bytes, $peOffset, 4) -ne ('PE' + [char]0 + [char]0)) {
        throw "PE header 格式不符：$Path"
    }

    switch ([BitConverter]::ToUInt16($bytes, $peOffset + 4)) {
        0x8664 { return 'x64' }
        0x014c { return 'x86' }
        default { throw "不支援的 PE 架構：$Path" }
    }
}

function Test-AppLocalVcRuntime {
    param(
        [Parameter(Mandatory)]
        [string]$RuntimeRoot
    )

    $manifestPath = Join-Path $RuntimeRoot 'ms4w_MSSQL\VC_RUNTIME_X64.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw '缺少 app-local VC++ x64 runtime 清單：ms4w_MSSQL/VC_RUNTIME_X64.json'
    }

    $manifest = Get-Content -LiteralPath $manifestPath -Encoding UTF8 -Raw | ConvertFrom-Json
    if ($manifest.schemaVersion -ne 1 -or $manifest.architecture -ne 'x64' -or $manifest.deployment -ne 'app-local') {
        throw 'VC++ runtime 清單格式或架構不符預期。'
    }

    $runtimeFiles = @($manifest.files)
    if ($runtimeFiles.Count -eq 0) {
        throw 'VC++ runtime 清單沒有檔案。'
    }

    foreach ($relativeDirectory in @($manifest.deploymentDirectories)) {
        $runtimeDirectory = Join-Path $RuntimeRoot ($relativeDirectory -replace '/', '\\')
        if (-not (Test-Path -LiteralPath $runtimeDirectory -PathType Container)) {
            throw "找不到 VC++ runtime 部署目錄：$relativeDirectory"
        }

        foreach ($runtimeFile in $runtimeFiles) {
            $runtimePath = Join-Path $runtimeDirectory $runtimeFile.name
            if (-not (Test-Path -LiteralPath $runtimePath -PathType Leaf)) {
                throw "缺少 app-local VC++ runtime：$relativeDirectory/$($runtimeFile.name)"
            }

            $actualHash = (Get-FileHash -LiteralPath $runtimePath -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($actualHash -ne $runtimeFile.sha256) {
                throw "app-local VC++ runtime 雜湊不符：$relativeDirectory/$($runtimeFile.name)"
            }

            $actualVersion = (Get-Item -LiteralPath $runtimePath).VersionInfo.FileVersion
            if ($actualVersion -ne $runtimeFile.fileVersion) {
                throw "app-local VC++ runtime 版本不符：$relativeDirectory/$($runtimeFile.name)"
            }
        }
    }

    $entryPoints = @(
        @{ Name = 'Apache'; RelativePath = 'ms4w_MSSQL\Apache\bin\httpd.exe' },
        @{ Name = 'PHP'; RelativePath = 'ms4w_MSSQL\Apache\php\php.exe' }
    )
    foreach ($entryPoint in $entryPoints) {
        $entryPointPath = Join-Path $RuntimeRoot $entryPoint.RelativePath
        $imports = @(Get-PeImportedDllNames -Path $entryPointPath)
        if ($imports -notcontains 'VCRUNTIME140.dll') {
            throw "$($entryPoint.Name) 沒有預期的 VCRUNTIME140.dll import：$($entryPoint.RelativePath)"
        }

        $appLocalRuntime = Join-Path (Split-Path -Parent $entryPointPath) 'vcruntime140.dll'
        if (-not (Test-Path -LiteralPath $appLocalRuntime -PathType Leaf)) {
            throw "$($entryPoint.Name) 旁缺少 VCRUNTIME140.dll：$($entryPoint.RelativePath)"
        }
    }

    return [pscustomobject][ordered]@{
        architecture = $manifest.architecture
        deployment = $manifest.deployment
        packageVersion = $manifest.source.packageVersion
        packageSha256 = $manifest.source.packageSha256
        files = $runtimeFiles
        deploymentDirectories = @($manifest.deploymentDirectories)
    }
}

function Test-AppLocalVcRuntimeX86 {
    param(
        [Parameter(Mandatory)]
        [string]$RuntimeRoot
    )

    $manifestPath = Join-Path $RuntimeRoot 'ms4w_MSSQL\VC_RUNTIME_X86.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw '缺少 app-local VC++ x86 runtime 清單：ms4w_MSSQL/VC_RUNTIME_X86.json'
    }

    $manifest = Get-Content -LiteralPath $manifestPath -Encoding UTF8 -Raw | ConvertFrom-Json
    if ($manifest.schemaVersion -ne 1 -or $manifest.architecture -ne 'x86' -or $manifest.deployment -ne 'app-local') {
        throw 'VC++ x86 runtime 清單格式或架構不符預期。'
    }

    $runtimeFiles = @($manifest.files)
    if ($runtimeFiles.Count -eq 0) {
        throw 'VC++ x86 runtime 清單沒有檔案。'
    }

    foreach ($relativeDirectory in @($manifest.deploymentDirectories)) {
        $runtimeDirectory = Join-Path $RuntimeRoot ($relativeDirectory -replace '/', '\')
        if (-not (Test-Path -LiteralPath $runtimeDirectory -PathType Container)) {
            throw "找不到 VC++ x86 runtime 部署目錄：$relativeDirectory"
        }

        foreach ($runtimeFile in $runtimeFiles) {
            $runtimePath = Join-Path $runtimeDirectory $runtimeFile.name
            if (-not (Test-Path -LiteralPath $runtimePath -PathType Leaf)) {
                throw "缺少 app-local VC++ x86 runtime：$relativeDirectory/$($runtimeFile.name)"
            }

            $actualHash = (Get-FileHash -LiteralPath $runtimePath -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($actualHash -ne $runtimeFile.sha256) {
                throw "app-local VC++ x86 runtime 雜湊不符：$relativeDirectory/$($runtimeFile.name)"
            }

            $actualVersion = (Get-Item -LiteralPath $runtimePath).VersionInfo.FileVersion
            if ($actualVersion -ne $runtimeFile.fileVersion) {
                throw "app-local VC++ x86 runtime 版本不符：$relativeDirectory/$($runtimeFile.name)"
            }
        }
    }

    $mapServerPath = Join-Path $RuntimeRoot 'ms4w_MSSQL\Apache\cgi-bin\mapserv.exe'
    if ((Get-PeArchitecture -Path $mapServerPath) -ne 'x86') {
        throw 'MapServer PE 架構並非 x86，不能載入 cgi-bin 的 x86 runtime。'
    }

    $imports = @(Get-PeImportedDllNames -Path $mapServerPath)
    if ($imports -notcontains 'VCRUNTIME140.dll') {
        throw 'MapServer 沒有預期的 VCRUNTIME140.dll import。'
    }

    return [pscustomobject][ordered]@{
        architecture = $manifest.architecture
        deployment = $manifest.deployment
        packageVersion = $manifest.source.packageVersion
        packageSha256 = $manifest.source.packageSha256
        files = $runtimeFiles
        deploymentDirectories = @($manifest.deploymentDirectories)
    }
}

$vcRuntime = @(
    Test-AppLocalVcRuntime -RuntimeRoot $resolvedRoot
    Test-AppLocalVcRuntimeX86 -RuntimeRoot $resolvedRoot
)

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
    vcRuntime = $vcRuntime
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
