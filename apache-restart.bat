@ECHO OFF

REM This restarts the apache service 

cd C:\ms4w_MSSQL\Apache\bin
httpd -k restart -n "Apache MS4W MSSQL Web Server: port 82"
cd ..\..

:ALL_DONE
