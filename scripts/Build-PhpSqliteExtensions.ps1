[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PhpSource,
    [Parameter(Mandatory)][string]$PhpDevel,
    [Parameter(Mandatory)][string]$SqliteSource,
    [Parameter(Mandatory)][string]$CompilerRoot,
    [Parameter(Mandatory)][string]$OutputDirectory,
    [string]$WindowsSdkRoot='C:\Program Files (x86)\Windows Kits\10',
    [string]$WindowsSdkVersion='10.0.26100.0'
)
$ErrorActionPreference='Stop'
$source=(Resolve-Path -LiteralPath $PhpSource).Path
$devel=(Resolve-Path -LiteralPath $PhpDevel).Path
$sqlite=(Resolve-Path -LiteralPath $SqliteSource).Path
$compiler=(Resolve-Path -LiteralPath $CompilerRoot).Path
$build=[IO.Path]::GetFullPath($OutputDirectory)
if(Test-Path -LiteralPath $build){throw 'OutputDirectory must be new; existing build output is never overwritten.'}
if((Get-Item -LiteralPath "$compiler\bin\Hostx64\x64\cl.exe").VersionInfo.FileVersion -notmatch '^19\.29\.') {throw 'Use the VS2019 14.29 compiler matching PHP 8.3 VS16.'}
if([IO.File]::ReadAllText("$source\main\php_version.h") -notmatch '#define PHP_VERSION "8\.3\.36"'){throw 'PHP source must be 8.3.36.'}
if([IO.File]::ReadAllText("$devel\include\main\php_version.h") -notmatch '#define PHP_VERSION "8\.3\.36"'){throw 'PHP development package must be 8.3.36 TS x64 VS16.'}
if([IO.File]::ReadAllText("$sqlite\sqlite3.h") -notmatch '#define SQLITE_VERSION\s+"3\.54\.1"'){throw 'SQLite source must be 3.54.1.'}
$phpInclude=Join-Path $devel 'include'
New-Item -ItemType Directory -Path $build | Out-Null
foreach($extension in 'pdo_sqlite','sqlite3') {Copy-Item -LiteralPath "$source\ext\$extension" -Destination "$build\$extension" -Recurse}
$driverPath=Join-Path $build 'pdo_sqlite\sqlite_driver.c'
$driver=[IO.File]::ReadAllText($driverPath).Replace("`r`n","`n")
$needle="`tif (PG(open_basedir) && *PG(open_basedir)) {`n`t`tsqlite3_set_authorizer(H->db, authorizer, NULL);"
if(!$driver.Contains($needle)){throw 'PDO patch anchor missing; inspect source rather than applying an unreviewed patch.'}
$driver=$driver.Replace($needle,"`tsqlite3_enable_load_extension(H->db, 1);`n`n"+$needle)
[IO.File]::WriteAllText($driverPath,$driver,[Text.UTF8Encoding]::new($false))
$savedEnvironment=@{Path=$env:PATH;Include=$env:INCLUDE;Lib=$env:LIB}
$env:PATH="$compiler\bin\Hostx64\x64;"+$env:PATH
$env:INCLUDE="$compiler\include;$WindowsSdkRoot\Include\$WindowsSdkVersion\ucrt;$WindowsSdkRoot\Include\$WindowsSdkVersion\shared;$WindowsSdkRoot\Include\$WindowsSdkVersion\um"
$env:LIB="$compiler\lib\x64;$WindowsSdkRoot\Lib\$WindowsSdkVersion\ucrt\x64;$WindowsSdkRoot\Lib\$WindowsSdkVersion\um\x64"
$common=@('/nologo','/c','/O2','/MD','/DWIN32','/D_WINDOWS','/DNDEBUG','/DPHP_WIN32','/DZEND_WIN32','/DZTS','/DZEND_DEBUG=0')
foreach($dir in @($phpInclude,"$phpInclude\main","$phpInclude\Zend","$phpInclude\TSRM","$phpInclude\win32","$phpInclude\ext",$sqlite)){$common+="/I$dir"}
Push-Location $build
try {
    & cl.exe /nologo /c /O2 /MD /DSQLITE_ENABLE_RTREE=1 /DSQLITE_ENABLE_COLUMN_METADATA=1 /DSQLITE_THREADSAFE=1 /DSQLITE_ENABLE_FTS3=1 /DSQLITE_ENABLE_FTS4=1 /DSQLITE_ENABLE_FTS5=1 /DSQLITE_ENABLE_MATH_FUNCTIONS=1 /Fosqlite3-core.obj "$sqlite\sqlite3.c"
    if($LASTEXITCODE -ne 0){throw 'SQLite core compilation failed'}
    & cl.exe @common /DCOMPILE_DL_PDO_SQLITE /Fopdo_sqlite.obj 'pdo_sqlite\pdo_sqlite.c'
    if($LASTEXITCODE -ne 0){throw 'pdo_sqlite.c compilation failed'}
    & cl.exe @common /DCOMPILE_DL_PDO_SQLITE /Fosqlite_driver.obj 'pdo_sqlite\sqlite_driver.c'
    if($LASTEXITCODE -ne 0){throw 'sqlite_driver.c compilation failed'}
    & cl.exe @common /DCOMPILE_DL_PDO_SQLITE /Fosqlite_statement.obj 'pdo_sqlite\sqlite_statement.c'
    if($LASTEXITCODE -ne 0){throw 'sqlite_statement.c compilation failed'}
    & link.exe /nologo /DLL /MACHINE:X64 /OUT:php_pdo_sqlite.dll pdo_sqlite.obj sqlite_driver.obj sqlite_statement.obj sqlite3-core.obj "$devel\lib\php8ts.lib"
    if($LASTEXITCODE -ne 0){throw 'PDO linking failed'}
    & cl.exe @common /DCOMPILE_DL_SQLITE3 /DZEND_ENABLE_STATIC_TSRMLS_CACHE=1 /Fophp_sqlite3.obj 'sqlite3\sqlite3.c'
    if($LASTEXITCODE -ne 0){throw 'PHP sqlite3 compilation failed'}
    & link.exe /nologo /DLL /MACHINE:X64 /OUT:php_sqlite3.dll php_sqlite3.obj sqlite3-core.obj "$devel\lib\php8ts.lib"
    if($LASTEXITCODE -ne 0){throw 'SQLite3 linking failed'}
} finally {
    Pop-Location
    $env:PATH=$savedEnvironment.Path;$env:INCLUDE=$savedEnvironment.Include;$env:LIB=$savedEnvironment.Lib
}
Get-FileHash (Join-Path $build 'php_pdo_sqlite.dll'),(Join-Path $build 'php_sqlite3.dll')
