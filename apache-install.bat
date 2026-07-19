@ECHO OFF
SETLOCAL EnableExtensions

REM 安裝前不覆蓋既有 runtime，避免破壞有效的本機設定。
SET "SOURCE_ROOT=%~dp0ms4w_MSSQL"
SET "TARGET_ROOT=C:\ms4w_MSSQL"
SET "SQLITE_EXT=C:\sqlite3_ext"
SET "SERVICE_NAME=ApacheMS4WMSSQLWebServer:port82"
SET "SERVICE_DISPLAY=Apache MS4W MSSQL Web Server: port 82"
SET "HTTPD=%TARGET_ROOT%\Apache\bin\httpd.exe"

NET SESSION >NUL 2>&1
IF ERRORLEVEL 1 (
    ECHO ERROR: Run this script from an elevated Command Prompt or PowerShell.
    EXIT /B 1
)

IF NOT EXIST "%SOURCE_ROOT%\Apache\bin\httpd.exe" (
    ECHO ERROR: MS4W runtime was not found at "%SOURCE_ROOT%".
    EXIT /B 1
)

IF NOT EXIST "%TARGET_ROOT%" (
    mklink /D "%TARGET_ROOT%" "%SOURCE_ROOT%"
    IF ERRORLEVEL 1 (
        ECHO ERROR: Cannot create "%TARGET_ROOT%" junction.
        EXIT /B 1
    )
) ELSE (
    ECHO INFO: "%TARGET_ROOT%" already exists; keeping the existing runtime.
)

IF NOT EXIST "%HTTPD%" (
    ECHO ERROR: "%HTTPD%" is missing. Check the existing runtime path.
    EXIT /B 1
)

IF NOT EXIST "%SOURCE_ROOT%\sqlite3_ext\mod_spatialite.dll" (
    ECHO ERROR: SpatiaLite runtime is missing from "%SOURCE_ROOT%\sqlite3_ext".
    EXIT /B 1
)

IF NOT EXIST "%SQLITE_EXT%" mkdir "%SQLITE_EXT%"
IF ERRORLEVEL 1 (
    ECHO ERROR: Cannot create "%SQLITE_EXT%".
    EXIT /B 1
)

REM 只補較新的 SQLite／SpatiaLite runtime，保留既有有效檔案。
robocopy "%SOURCE_ROOT%\sqlite3_ext" "%SQLITE_EXT%" /E /XO /COPY:DAT /DCOPY:DAT
SET "ROBOCOPY_EXIT=%ERRORLEVEL%"
IF %ROBOCOPY_EXIT% GEQ 8 (
    ECHO ERROR: SQLite runtime copy failed with robocopy exit code %ROBOCOPY_EXIT%.
    EXIT /B %ROBOCOPY_EXIT%
)

"%HTTPD%" -t
IF ERRORLEVEL 1 (
    ECHO ERROR: Apache configuration validation failed; service was not changed.
    EXIT /B 1
)

sc query "%SERVICE_NAME%" >NUL 2>&1
IF ERRORLEVEL 1 (
    sc create "%SERVICE_NAME%" binPath= "%HTTPD% -k runservice" start= auto displayname= "%SERVICE_DISPLAY%"
    IF ERRORLEVEL 1 GOTO :SERVICE_ERROR
) ELSE (
    sc query "%SERVICE_NAME%" | findstr /C:"RUNNING" >NUL
    IF NOT ERRORLEVEL 1 (
        sc stop "%SERVICE_NAME%" >NUL
        CALL :WAIT_FOR_STOP
        IF ERRORLEVEL 1 GOTO :SERVICE_ERROR
    )
    sc config "%SERVICE_NAME%" binPath= "%HTTPD% -k runservice" start= auto displayname= "%SERVICE_DISPLAY%"
    IF ERRORLEVEL 1 GOTO :SERVICE_ERROR
)

sc start "%SERVICE_NAME%" >NUL
IF ERRORLEVEL 1 GOTO :SERVICE_ERROR
CALL :WAIT_FOR_RUNNING
IF ERRORLEVEL 1 GOTO :SERVICE_ERROR

ECHO Apache service is running on http://127.0.0.1:82/
EXIT /B 0

:WAIT_FOR_STOP
SET /A WAIT_SECONDS=0
:WAIT_FOR_STOP_LOOP
sc query "%SERVICE_NAME%" | findstr /C:"STOPPED" >NUL
IF NOT ERRORLEVEL 1 EXIT /B 0
IF %WAIT_SECONDS% GEQ 30 EXIT /B 1
timeout /t 1 /nobreak >NUL
SET /A WAIT_SECONDS+=1
GOTO :WAIT_FOR_STOP_LOOP

:WAIT_FOR_RUNNING
SET /A WAIT_SECONDS=0
:WAIT_FOR_RUNNING_LOOP
sc query "%SERVICE_NAME%" | findstr /C:"RUNNING" >NUL
IF NOT ERRORLEVEL 1 EXIT /B 0
IF %WAIT_SECONDS% GEQ 30 EXIT /B 1
timeout /t 1 /nobreak >NUL
SET /A WAIT_SECONDS+=1
GOTO :WAIT_FOR_RUNNING_LOOP

:SERVICE_ERROR
ECHO ERROR: Apache service configuration or startup failed.
EXIT /B 1
