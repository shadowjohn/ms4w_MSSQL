@ECHO OFF

REM This stops and uninstalls apache service

cd C:\ms4w_MSSQL\Apache\bin
httpd -k stop -n "Apache MS4W MSSQL Web Server: port 82"
httpd -k uninstall -n "Apache MS4W MSSQL Web Server: port 82"
cd ..\..

:ALL_DONE
