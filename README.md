# ms4w_MSSQL

本專案整理一套 Windows 可攜式 GIS Web / GDAL 工具環境，基底為 MS4W，並加上 Easymap 產線常用的 MSSQL、GDAL、SQLite / SpatiaLite、Apache、PHP、Python 等執行元件。

主要用途是讓 Easymap、DEM terrain 轉檔、SHP / SQLite 建物轉 3D Tiles、MapServer / GDAL 指令工具在 Windows 機器上可以快速建立一致環境，不需要每台機器重新拼湊相依套件。

## 產出定位

- MS4W 根目錄：`ms4w_MSSQL/`
- GDAL 指令工具：`ms4w_MSSQL/GDAL/`
- Apache / PHP / CGI：`ms4w_MSSQL/Apache/`
- MapServer plugins：`ms4w_MSSQL/msplugins/`
- GDAL data：`ms4w_MSSQL/gdaldata/`
- GDAL plugins：`ms4w_MSSQL/gdalplugins/`
- PROJ data：`ms4w_MSSQL/proj/`
- Python runtime：`ms4w_MSSQL/python/`
- SQLite / SpatiaLite extension：`ms4w_MSSQL/sqlite3_ext/`

這個 repo 的重點不是開發 MS4W 本體，而是保存一套已知可用、可複製、可被其他 GIS 小工具引用的 Windows runtime。

## 目前定版

目前基底版本：

```text
MS4W 4.0.4
```

## 下載版本

可直接使用的 Windows x64 壓縮包放在 [GitHub Releases](https://github.com/shadowjohn/ms4w_MSSQL/releases)。每個版本會一併提供 `SHA256SUMS.txt` 與 `release-manifest.json`，方便核對下載檔、來源 commit、核心工具版本與簽章狀態。

主要執行檔目前沒有 Authenticode 簽章，Windows 可能顯示未知發行者警告。下載後請先核對 SHA-256，再完整解壓縮；不要只複製單一 EXE 或 DLL。

這個 ZIP 已採用 **app-local Microsoft Visual C++ v14 x64 runtime**：Apache、PHP 與 MapServer 所需的 runtime DLL 已放在各自的實際載入目錄，不需要使用者另外安裝 Visual C++ Redistributable。runtime 來源版本與每個 DLL 的 SHA-256 請見 `ms4w_MSSQL/VC_RUNTIME_X64.json`；不要自行以來路不明的 DLL 覆蓋。

主要 runtime 版本：

| 元件 | 版本 / 狀態 | 位置 |
|---|---|---|
| Apache | Apache/2.4.68 Win64，Apache Lounge VS18 build 2026-06-17 | `ms4w_MSSQL/Apache/bin/httpd.exe` |
| PHP | PHP 8.3.32 ZTS x64，Visual C++ 2019，含 Zend OPcache | `ms4w_MSSQL/Apache/php/php.exe` |
| PHP Apache module | `php8apache2_4.dll` | `ms4w_MSSQL/Apache/php/` |
| PHP legacy CGI | PHP 5.3.2，保留於 CGI 目錄，主要作為舊版相容檢查 | `ms4w_MSSQL/Apache/cgi-bin/php.exe` |
| MapServer | MapServer 7.7.0-dev，MS4W build string 顯示 4.0.5 | `ms4w_MSSQL/Apache/cgi-bin/mapserv.exe` |
| GDAL / OGR | GDAL 2.4.0，released 2018-12-14 | `ms4w_MSSQL/GDAL/` |
| Python | Python 3.7.8 | `ms4w_MSSQL/python/python.exe` |
| SQLite CLI | SQLite 3.42.0 | `ms4w_MSSQL/sqlite3_ext/sqlite3.exe` |
| OpenSSL | OpenSSL 3.6.3 | `ms4w_MSSQL/Apache/bin/openssl.exe` |

這包也包含編譯後的 PHP SQLite / PDO / GeoSQLite 相關 DLL，包含：

- `php_pdo_sqlite.dll`
- `php_sqlite3.dll`
- `mod_spatialite.dll`
- `libspatialite-4.dll`
- `spatialite.dll`
- `sqlite3.dll`
- `libgeos.dll`
- `libgeos_c.dll`

其中 `pdo_geosqlite` / GeoSQLite 支援是這個整理版的重要用途之一，用來讓舊 Easymap / PHP 程式可以透過 PDO / SQLite 路線讀寫帶空間能力的 SQLite 資料，而不是只依賴純文字 WKT 或外部轉檔。

PHP 8.3.32 已啟用 `sqlsrv`、`pdo_sqlsrv`、`pdo_sqlite`、`sqlite3`。其中 `php_pdo_sqlite.dll` 為可執行 `load_extension()` 的重編版本，已以 PDO 載入 SpatiaLite 5.1.0 驗證。Apache FastCGI 必須保留 `C:/sqlite3_ext` 於 PATH，否則 SpatiaLite 的相依 DLL 無法被載入。

已知主要使用情境：

- Easymap / MapServer 本機 Apache CGI 測試環境
- GDAL raster / vector 轉檔
- DEM / GeoTIFF / VRT 處理
- SQLite / SpatiaLite 指令與 DLL 相依
- SHP、GeoJSON、GeoPackage、MSSQL 空間資料轉換
- terrain / building 產線中的 GDAL helper

## 安裝方式

請在系統管理員權限的 Command Prompt 或 PowerShell 執行：

```bat
apache-install.bat
```

安裝腳本會建立或沿用固定 runtime 位置：

```text
C:\ms4w_MSSQL
C:\sqlite3_ext
```

並建立 Apache service：

```text
Apache MS4W MSSQL Web Server: port 82
```

這個固定位置是為了讓既有 Easymap、GDAL、SQLite extension 與產線腳本可以用一致路徑找到工具。若要改路徑，請同步檢查 `setenv.bat`、Apache 設定與依賴此環境的外部工具。

`apache-install.bat` 會先驗證系統管理員權限與 `httpd -t`，不會刪除既有 `C:\ms4w_MSSQL` runtime；`C:\sqlite3_ext` 以較新檔案補齊。這可避免重裝時覆蓋已驗證的本機設定。

## 服務操作

重啟 Apache：

```bat
apache-restart.bat
```

移除 Apache service：

```bat
apache-uninstall.bat
```

移除腳本只刪除 service，保留 `C:\ms4w_MSSQL`、`C:\sqlite3_ext` 與所有 runtime／資料檔案。

如果服務啟動失敗，先檢查：

1. 是否以系統管理員權限執行。
2. `C:\ms4w_MSSQL` 是否正確指到本專案的 `ms4w_MSSQL/`。
3. port 82 是否被其他服務佔用。
4. `ms4w_MSSQL/Apache/logs/` 內的 Apache log。

## 命令列環境

執行 GDAL、MapServer、Python、PHP 等命令前，可先載入環境變數：

```bat
C:\ms4w_MSSQL\setenv.bat
```

主要設定包含：

- `PATH`
- `GDAL_DATA`
- `GDAL_DRIVER_PATH`
- `PROJ_LIB`
- `CURL_CA_BUNDLE`
- `SSL_CERT_FILE`
- `OPENSSL_CONF`
- `PDAL_DRIVER_PATH`

載入後可直接執行：

```bat
gdalinfo --version
ogrinfo --version
gdalwarp --help
ogr2ogr --help
```

若外部 Node.js / PHP / PowerShell 產線工具只需要 GDAL，也可以直接呼叫：

```text
C:\ms4w_MSSQL\GDAL\gdalinfo.exe
C:\ms4w_MSSQL\GDAL\gdalwarp.exe
C:\ms4w_MSSQL\GDAL\ogr2ogr.exe
C:\ms4w_MSSQL\GDAL\gdallocationinfo.exe
```

## 常用 GDAL 範例

查看 raster 資訊：

```bat
C:\ms4w_MSSQL\GDAL\gdalinfo.exe input.tif
```

轉成 EPSG:4326 GeoTIFF：

```bat
C:\ms4w_MSSQL\GDAL\gdalwarp.exe -t_srs EPSG:4326 input.tif output-4326.tif
```

建立 VRT：

```bat
C:\ms4w_MSSQL\GDAL\gdalbuildvrt.exe output.vrt input-a.tif input-b.tif
```

查詢指定經緯度高程：

```bat
C:\ms4w_MSSQL\GDAL\gdallocationinfo.exe -wgs84 -valonly terrain-4326.tif 120.67 24.15
```

SHP / GeoPackage / SQLite 轉換：

```bat
C:\ms4w_MSSQL\GDAL\ogr2ogr.exe -f GPKG output.gpkg input.shp
```

## 與其他工具的關係

這套 runtime 是多個 3WA GIS 小工具的共用基礎。

- [shadowjohn/dem20M_terrain](https://github.com/shadowjohn/dem20M_terrain)：使用 GDAL 處理 DEM、VRT、GeoTIFF 與 terrain 前處理。
- `shp_build_building`：使用 GDAL / `gdallocationinfo` 對建物 footprint 採樣 terrain 高程，再產 3D Tiles。
- Easymap / MapServer：使用 Apache、PHP、CGI、MapServer plugin 與 MSSQL 空間資料支援。

原則上，資料產線專案不要各自夾帶一份 GDAL；統一引用這個 runtime，版本比較好控，也比較容易重現問題。

## 目錄維護規則

建議簽入：

- README / 文件
- 安裝、重啟、移除服務用 batch
- 需要固定保存的 runtime 檔案
- MS4W / GDAL / MapServer 必要設定

不建議簽入：

- Apache log
- PHP error log
- tmp / cache
- 本機測試上傳資料
- 私有站台資料
- 帳密、連線字串、憑證與 token

若有站台專屬設定，優先放在私有部署環境，不要寫進公開 README。

## 驗證方式

安裝後建議依序確認：

```bat
dir C:\ms4w_MSSQL
C:\ms4w_MSSQL\setenv.bat
gdalinfo --version
ogrinfo --version
```

Apache service：

```bat
sc query "Apache MS4W MSSQL Web Server: port 82"
```

瀏覽器確認：

```text
http://localhost:82/
```

若有 MapServer / Easymap CGI 專案，再確認對應 endpoint 是否可正常回應。

## 常見問題

### 找不到 VCRUNTIME140.dll

正式 ZIP 已內含 x64 app-local VC++ runtime。請確認是**完整解壓**後，從原始目錄執行 `apache-install.bat`，不要只複製 `httpd.exe` 或 `Apache/bin` 的部分檔案。若仍出現此訊息，請先比對 Release 的 SHA-256，再確認防毒軟體沒有隔離 `Apache/bin/vcruntime140.dll`。

### 找不到 GDAL DLL

先執行：

```bat
C:\ms4w_MSSQL\setenv.bat
```

若是外部程式直接呼叫 GDAL exe，請確認工作行程能讀到 `C:\ms4w_MSSQL\Apache\cgi-bin`、`C:\ms4w_MSSQL\GDAL` 與相關 DLL 目錄。

### Apache service 啟動失敗

最快恢復路徑：

```bat
apache-uninstall.bat
apache-install.bat
```

若仍失敗，再看 `ms4w_MSSQL/Apache/logs/error_log.txt` 與 Windows Event Viewer。

### SQLite / SpatiaLite extension 載入失敗

確認 `C:\sqlite3_ext` 已由 `apache-install.bat` 複製，且外部程式找得到相關 DLL。這個目錄是為了降低不同工具載入 SpatiaLite DLL 時的路徑差異。

## 安全注意

這是一套開發與內部產線 runtime，不建議直接暴露在公開網路。

若要放到正式環境，至少要確認：

1. Apache 只開必要 port。
2. CGI / PHP endpoint 沒有測試頁或危險工具。
3. log、tmp、upload 目錄不公開列目錄。
4. 連線字串與帳密不進版控。
5. 只把需要公開的 web root 對外。

## 來源

本 repo 作為 3WA / Easymap 工具鏈的 Windows runtime 整理版，公開來源位於：

```text
https://github.com/shadowjohn/ms4w_MSSQL
```

文件風格與產線整理方式對齊：

```text
https://github.com/shadowjohn/dem20M_terrain
```
