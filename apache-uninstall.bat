@ECHO OFF
SETLOCAL EnableExtensions

REM 移除 service，不刪除 runtime junction、SQLite extension 或使用者資料。
SET "SERVICE_NAME=ApacheMS4WMSSQLWebServer:port82"

NET SESSION >NUL 2>&1
IF ERRORLEVEL 1 (
    ECHO ERROR: Run this script from an elevated Command Prompt or PowerShell.
    EXIT /B 1
)

sc query "%SERVICE_NAME%" >NUL 2>&1
IF ERRORLEVEL 1 (
    ECHO INFO: Apache service is not installed.
    EXIT /B 0
)

sc query "%SERVICE_NAME%" | findstr /C:"RUNNING" >NUL
IF NOT ERRORLEVEL 1 (
    sc stop "%SERVICE_NAME%" >NUL
    CALL :WAIT_FOR_STOP
    IF ERRORLEVEL 1 (
        ECHO ERROR: Apache service did not stop within 30 seconds.
        EXIT /B 1
    )
)

sc delete "%SERVICE_NAME%"
IF ERRORLEVEL 1 (
    ECHO ERROR: Apache service deletion failed.
    EXIT /B 1
)

ECHO Apache service removed. Runtime files were kept.
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
