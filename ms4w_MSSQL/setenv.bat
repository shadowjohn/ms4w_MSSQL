@ECHO OFF

REM Execute this file before running the GDAL, MapServer, and other commandline utilities.
REM After executing this file you should be able 
REM to run the utilities from any commandline location.

set PATH=C:\ms4w_MSSQL;C:\ms4w_MSSQL\Apache\cgi-bin;C:\ms4w_MSSQL\tools\gdal-ogr;C:\ms4w_MSSQL\tools\mapserv;C:\ms4w_MSSQL\tools\shapelib;C:\ms4w_MSSQL\proj\bin;C:\ms4w_MSSQL\tools\shp2tile;C:\ms4w_MSSQL\tools\shpdiff;C:\ms4w_MSSQL\tools\avce00;C:\ms4w_MSSQL\gdalbindings\python\gdal;C:\ms4w_MSSQL\tools\php;C:\ms4w_MSSQL\tools\mapcache;C:\ms4w_MSSQL\tools\berkeley-db;C:\ms4w_MSSQL\tools\sqlite;C:\ms4w_MSSQL\tools\spatialite;C:\ms4w_MSSQL\tools\unixutils;C:\ms4w_MSSQL\tools\openssl;C:\ms4w_MSSQL\tools\curl;C:\ms4w_MSSQL\tools\geotiff;C:\ms4w_MSSQL\tools\jpeg;C:\ms4w_MSSQL\tools\protobuf;C:\ms4w_MSSQL\Python;C:\ms4w_MSSQL\Python\Scripts;C:\ms4w_MSSQL\tools\osm2pgsql;C:\ms4w_MSSQL\tools\netcdf;C:\ms4w_MSSQL\tools\pdal;%PATH%
echo GDAL, mapserv, Python, PHP, and commandline MS4W tools path set

set GDAL_DATA=C:\ms4w_MSSQL\gdaldata

set GDAL_DRIVER_PATH=C:\ms4w_MSSQL\gdalplugins

set PROJ_LIB=C:\ms4w_MSSQL\proj\nad

set CURL_CA_BUNDLE=C:\ms4w_MSSQL\Apache\conf\ca-bundle\cacert.pem

set SSL_CERT_FILE=C:\ms4w_MSSQL\Apache\conf\ca-bundle\cacert.pem

set OPENSSL_CONF=C:\ms4w_MSSQL\tools\openssl\openssl.cnf

set PDAL_DRIVER_PATH=C:\ms4w_MSSQL\Apache\cgi-bin

:ALL_DONE
