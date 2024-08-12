@ECHO OFF

REM This installs and starts the apache service 
SET mypath=%~dp0
echo %mypath%
rd C:\ms4w_MSSQL
rd C:\sqlite3_ext
mklink /d C:\ms4w_MSSQL %mypath%ms4w_MSSQL
mkdir c:\sqlite3_ext
xcopy /-y  %mypath%ms4w_MSSQL\sqlite3_ext\*.* C:\sqlite3_ext\

cd C:\ms4w_MSSQL\Apache\bin
httpd -k install -n "Apache MS4W MSSQL Web Server: port 82"
net start "Apache MS4W MSSQL Web Server: port 82"
cd ..\..

:ALL_DONE
