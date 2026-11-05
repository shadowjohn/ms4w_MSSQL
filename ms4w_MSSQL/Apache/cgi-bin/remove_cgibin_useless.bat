@ECHO OFF
SETLOCAL EnableExtensions DisableDelayedExpansion

REM Put this BAT inside Apache\cgi-bin. It only cleans its own directory.
REM Exact file names only. No recursion, backups, service changes, or shared DLL cleanup.
IF DEFINED GATEWAY_INTERFACE (
    ECHO ERROR: Run this BAT locally, not through CGI.
    EXIT /B 2
)

SET "CLEANUP_ROOT=%~dp0"
SET "DRY_RUN=0"
SET "NO_PAUSE=0"
SET "SCRIPT_EXIT=0"

:ARGS
IF "%~1"=="" GOTO :RUN
IF /I "%~1"=="/dry-run" (
    SET "DRY_RUN=1"
    SHIFT
    GOTO :ARGS
)
IF /I "%~1"=="/nopause" (
    SET "NO_PAUSE=1"
    SHIFT
    GOTO :ARGS
)
IF /I "%~1"=="/?" (
    CALL :USAGE
    GOTO :FINISH
)
ECHO ERROR: Unknown option "%~1".
CALL :USAGE
SET "SCRIPT_EXIT=2"
GOTO :FINISH

:RUN
CALL :MAIN
SET "SCRIPT_EXIT=%ERRORLEVEL%"
:FINISH
IF "%NO_PAUSE%"=="0" PAUSE
EXIT /B %SCRIPT_EXIT%

:MAIN
IF NOT EXIST "%CLEANUP_ROOT%mapserv.exe" (
    ECHO ERROR: mapserv.exe is missing beside this BAT. Put it inside Apache\cgi-bin.
    EXIT /B 2
)
IF NOT EXIST "%CLEANUP_ROOT%..\php\php-cgi.exe" (
    ECHO ERROR: Apache\php\php-cgi.exe is missing. Set up the main PHP runtime first.
    EXIT /B 2
)

SET /A REMOVED=0, MISSING=0, KEPT=0, FAILED=0, PLANNED=0 >NUL
ECHO Target: "%CLEANUP_ROOT%"
IF "%DRY_RUN%"=="1" ECHO Preview only. No files will be deleted.
ECHO.

REM Retired PHP runtimes. The supported PHP lives in Apache\php.
CALL :REMOVE_FILE "php.exe"
CALL :REMOVE_FILE "php.ini"
CALL :REMOVE_FILE "php-cgi.exe"
CALL :REMOVE_FILE "php-win.exe"
CALL :REMOVE_FILE "php5apache.dll"
CALL :REMOVE_FILE "php5apache2.dll"
CALL :REMOVE_FILE "php5apache2_2.dll"
CALL :REMOVE_FILE "php5apache2_2_filter.dll"
CALL :REMOVE_FILE "php5apache2_filter.dll"
CALL :REMOVE_FILE "php5apache_hooks.dll"
CALL :REMOVE_FILE "php5embed.lib"
CALL :REMOVE_FILE "php5isapi.dll"
CALL :REMOVE_FILE "php5nsapi.dll"
CALL :REMOVE_FILE "php5pi3web.dll"
CALL :REMOVE_FILE "php5ts.dll"
CALL :REMOVE_FILE "php7embed.lib"
CALL :REMOVE_FILE "php7ts.dll"

REM Build generators and the OWT GIF example; not needed to run MapServer.
CALL :REMOVE_FILE "lemon.exe"
CALL :REMOVE_FILE "mkkeywordhash.exe"
CALL :REMOVE_FILE "mksourceid.exe"
CALL :REMOVE_FILE "protoc.exe"
CALL :REMOVE_FILE "protoc-gen-c.exe"
CALL :REMOVE_FILE "gifsample.exe"

REM Keep these generic sample names if another host has changed their contents.
CALL :REMOVE_SAMPLE "printenv.pl" "940DE9D9CA9F78B6E1873CE70254CD448F9CF961A7984E127B5CD3F4D8BFC659"
CALL :REMOVE_SAMPLE "test.png" "B2AF052946E02811CB570ACF38C33F7D4C30B08E00AED3AE565D8E2031A9FBAA"

ECHO.
ECHO Removed: %REMOVED%  Missing: %MISSING%  Kept: %KEPT%  Failed: %FAILED%  Would delete: %PLANNED%
IF NOT "%FAILED%"=="0" (
    ECHO ERROR: Some files could not be removed. Check permissions and running programs.
    ECHO If needed, right-click this BAT and choose "Run as administrator".
    EXIT /B 1
)
EXIT /B 0

:REMOVE_SAMPLE
IF NOT EXIST "%CLEANUP_ROOT%%~1" GOTO :REMOVE_FILE
IF EXIST "%CLEANUP_ROOT%%~1\" GOTO :REMOVE_FILE
SET "CGI_CLEANUP_SAMPLE=%CLEANUP_ROOT%%~1"
SET "CGI_CLEANUP_HASH=%~2"
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -NonInteractive -Command "try { $sha=[Security.Cryptography.SHA256]::Create(); $hash=[BitConverter]::ToString($sha.ComputeHash([IO.File]::ReadAllBytes($env:CGI_CLEANUP_SAMPLE))).Replace('-',''); $sha.Dispose(); if ($hash -eq $env:CGI_CLEANUP_HASH) { exit 0 } } catch {}; exit 1" >NUL 2>&1
IF ERRORLEVEL 1 (
    ECHO KEEP: "%~1" differs from the known sample, or its hash could not be checked.
    SET /A KEPT+=1 >NUL
    EXIT /B 0
)
GOTO :REMOVE_FILE

:REMOVE_FILE
IF NOT EXIST "%CLEANUP_ROOT%%~1" (
    SET /A MISSING+=1 >NUL
    EXIT /B 0
)
IF EXIST "%CLEANUP_ROOT%%~1\" (
    ECHO ERROR: "%~1" is a directory; keeping it.
    SET /A FAILED+=1 >NUL
    EXIT /B 1
)
IF "%DRY_RUN%"=="1" (
    ECHO WOULD DELETE: "%~1"
    SET /A PLANNED+=1 >NUL
    EXIT /B 0
)
DEL /Q "%CLEANUP_ROOT%%~1" >NUL 2>&1
IF EXIST "%CLEANUP_ROOT%%~1" (
    ECHO ERROR: Could not remove "%~1".
    SET /A FAILED+=1 >NUL
    EXIT /B 1
)
ECHO REMOVED: "%~1"
SET /A REMOVED+=1 >NUL
EXIT /B 0

:USAGE
ECHO Usage: remove_cgibin_useless.bat [/dry-run] [/nopause]
ECHO Place this BAT inside Apache\cgi-bin and run it locally.
ECHO /dry-run  List the matching files without deleting them.
ECHO /nopause  Return immediately and preserve the exit code.
ECHO Shared DLLs, MapServer, optional GIS features, maps and site data are kept.
EXIT /B 0
