@ECHO OFF
SETLOCAL EnableExtensions

SET "SERVICE_NAME=ApacheMS4WMSSQLWebServer:port82"

NET SESSION >NUL 2>&1
IF ERRORLEVEL 1 (
    ECHO ERROR: Run this script from an elevated Command Prompt or PowerShell.
    EXIT /B 1
)

sc query "%SERVICE_NAME%" >NUL 2>&1
IF ERRORLEVEL 1 (
    ECHO ERROR: Apache service is not installed. Run apache-install.bat first.
    EXIT /B 1
)

sc stop "%SERVICE_NAME%" >NUL
CALL :WAIT_FOR_STOP
IF ERRORLEVEL 1 (
    ECHO ERROR: Apache service did not stop within 30 seconds.
    EXIT /B 1
)

sc start "%SERVICE_NAME%" >NUL
IF ERRORLEVEL 1 (
    ECHO ERROR: Apache service startup failed.
    EXIT /B 1
)
CALL :WAIT_FOR_RUNNING
IF ERRORLEVEL 1 (
    ECHO ERROR: Apache service did not reach RUNNING within 30 seconds.
    EXIT /B 1
)

ECHO Apache service restarted on http://127.0.0.1:82/
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
