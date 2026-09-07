# Windows 重編 PHP 8.3.32 SQLite extensions

本文件記錄 MS4W MSSQL runtime 兩個獨立 PHP SQLite extension 的重編、安裝與驗證方式：

- `php_pdo_sqlite.dll`：讓受控的 PDO SQLite connection 可呼叫 `load_extension()` 載入 SpatiaLite。
- `php_sqlite3.dll`：讓 `new SQLite3(...)` 支援 RTree virtual table，供 Easymap 的 `idx_*_GEOMETRY` 空間索引使用。

兩個 DLL 必須分別編譯；重編其中之一不會改變另一個的行為。

## 1. 目前 runtime ABI

所有產物都必須和以下 ABI 一致：

| 項目 | 值 |
|---|---|
| PHP | 8.3.32 |
| 架構 | x64 |
| Thread Safety | ZTS / TS |
| PHP Extension Build | `API20230831,TS,VS16` |
| 編譯器 | Visual C++ 2019 / vc16（MSVC 14.29） |
| 現役 runtime | `C:\ms4w_MSSQL\Apache\php\` |

先以現役 PHP 核對版本與 extension：

```bat
C:\ms4w_MSSQL\Apache\php\php.exe -v
C:\ms4w_MSSQL\Apache\php\php.exe -i | findstr /I "Thread Safety PHP Extension Build Compiler"
C:\ms4w_MSSQL\Apache\php\php.exe -m | findstr /I "pdo_sqlite sqlite3"
```

不要混用 VS2022 / vc17 DLL；典型錯誤是 `linked with 14.4x, but the core is linked with 14.29`。

## 2. 準備 source、SDK 與 SQLite deps

需要 PHP SDK、VS2019 Build Tools（含 C++ desktop workload）與 Windows SDK。此機器已使用：

```text
C:\php-sdk\
C:\php-sdk\phpmaster\vs16\x64\php-8.3.32\
C:\php-sdk\phpmaster\vs16\x64\deps\include\sqlite3.h
C:\php-sdk\phpmaster\vs16\x64\deps\include\sqlite3ext.h
C:\php-sdk\phpmaster\vs16\x64\deps\lib\libsqlite3_a.lib
```

若尚未取得 source，應抓官方完全相同的 PHP tag：

```bat
git clone --depth 1 --branch php-8.3.32 https://github.com/php/php-src.git C:\php-sdk\phpmaster\vs16\x64\php-8.3.32
```

`configure.js` 對 shared SQLite extension 會優先檢查 `libsqlite3.lib`，再 fallback 到 `libsqlite3_a.lib`。不可隨意複製不明來源的 SQLite library；目前已驗證的 `libsqlite3_a.lib` 產物回報 SQLite 3.46.0，且可建立 RTree table。最終是否支援 RTree 必須用第 6 節的實際 SQL 驗證。

## 3. 開啟 vc16 SDK shell

以系統管理員身分開啟 **Command Prompt**，在同一個命令視窗執行。此主機的 `phpsdk-starter.bat` 不會完整保留 SDK include/lib 環境，因此要補上既有工具與 Windows SDK 路徑；若日後 MSVC 或 Windows SDK 版本變更，更新對應目錄名稱。

```bat
call C:\php-sdk\phpsdk-starter.bat -c vc16 -a x64

set "PATH=C:\php-sdk\bin;C:\php-sdk\msys2\usr\bin;C:\Program Files (x86)\Windows Kits\10\bin\10.0.19041.0\x64;C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools\VC\Tools\MSVC\14.29.30133\bin\Hostx64\x64;%PATH%"
set "INCLUDE=C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools\VC\Tools\MSVC\14.29.30133\include;C:\Program Files (x86)\Windows Kits\10\Include\10.0.19041.0\ucrt;C:\Program Files (x86)\Windows Kits\10\Include\10.0.19041.0\shared;C:\Program Files (x86)\Windows Kits\10\Include\10.0.19041.0\um;C:\Program Files (x86)\Windows Kits\10\Include\10.0.19041.0\winrt;C:\Program Files (x86)\Windows Kits\10\Include\10.0.19041.0\cppwinrt"
set "LIB=C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools\VC\Tools\MSVC\14.29.30133\lib\x64;C:\Program Files (x86)\Windows Kits\10\Lib\10.0.19041.0\ucrt\x64;C:\Program Files (x86)\Windows Kits\10\Lib\10.0.19041.0\um\x64"

where cl
where link
where nmake
where bison
where re2c
where mc
```

`bison.exe` / `re2c.exe` 位於 PHP SDK 的 `msys2\usr\bin`；`mc.exe` 位於 Windows SDK。

## 4. 重編 `php_pdo_sqlite.dll`

### 4.1 只允許 PDO 載入 SpatiaLite

編輯：

```text
C:\php-sdk\phpmaster\vs16\x64\php-8.3.32\ext\pdo_sqlite\sqlite_driver.c
```

在 `sqlite3_open_v2()` 成功、`open_basedir` 判斷之前加入：

```c
if (i != SQLITE_OK) {
    pdo_sqlite_error(dbh);
    goto cleanup;
}

sqlite3_enable_load_extension(H->db, 1);

if (PG(open_basedir) && *PG(open_basedir)) {
```

這只用於程式自行決定 extension 名稱的受控 connection。不可將可執行任意 SQL 的輸入交給不受信任使用者。

### 4.2 編譯

在第 3 節的同一個 SDK shell：

```bat
cd /d C:\php-sdk\phpmaster\vs16\x64\php-8.3.32
if exist Makefile nmake clean
call buildconf.bat
cscript /nologo /e:jscript configure.js "--disable-all" "--enable-cli" "--enable-pdo=shared" "--with-pdo-sqlite=shared" "--with-php-build=C:\php-sdk\phpmaster\vs16\x64\deps"
nmake php_pdo_sqlite.dll
```

輸出檔：

```text
C:\php-sdk\phpmaster\vs16\x64\php-8.3.32\x64\Release_TS\php_pdo_sqlite.dll
```

## 5. 重編 RTree `php_sqlite3.dll`

`php_sqlite3.dll` 不需要第 4.1 節的 source patch；RTree 能力來自 SQLite deps library。每次換 configure 選項前先 `nmake clean`，避免 PDO 與 SQLite3 的 build setting 混用。

```bat
cd /d C:\php-sdk\phpmaster\vs16\x64\php-8.3.32
if exist Makefile nmake clean
call buildconf.bat
cscript /nologo /e:jscript configure.js "--disable-all" "--enable-cli" "--with-sqlite3=shared" "--with-php-build=C:\php-sdk\phpmaster\vs16\x64\deps"
nmake php_sqlite3.dll
```

預期 configure output 包含：

```text
Checking for library libsqlite3.lib;libsqlite3_a.lib ... <in deps path>
Enabling extension ext\sqlite3 [shared]
```

輸出檔：

```text
C:\php-sdk\phpmaster\vs16\x64\php-8.3.32\x64\Release_TS\php_sqlite3.dll
```

## 6. 隔離驗證

先用現役 `php.exe` 加載候選 DLL，避免未驗證就覆蓋 runtime：

```bat
C:\ms4w_MSSQL\Apache\php\php.exe -n -d extension=C:\php-sdk\phpmaster\vs16\x64\php-8.3.32\x64\Release_TS\php_sqlite3.dll -r "$db=new SQLite3(':memory:'); if (!$db->exec('CREATE VIRTUAL TABLE test_rtree USING rtree(id,xmin,xmax,ymin,ymax)')) { fwrite(STDERR,$db->lastErrorMsg()); exit(1); } echo 'RTree OK',PHP_EOL;"
```

預期輸出 `RTree OK`。這是判定 RTree 是否可用的依據；不要只以 `PRAGMA compile_options` 判斷。

PDO / SpatiaLite 則應確認：

```php
$pdo = new PDO('sqlite::memory:');
$pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
$pdo->exec("SELECT load_extension('mod_spatialite.dll')");
echo $pdo->query('SELECT spatialite_version()')->fetchColumn(), PHP_EOL;
```

`php.ini` 必須保留：

```ini
extension=pdo_sqlite
extension=sqlite3
sqlite3.extension_dir = C:\sqlite3_ext\
```

Apache FastCGI 的 `Apache\conf\httpd.conf` 必須保留：

```apache
FcgidInitialEnv PHPRC "${PHPROOT}"
FcgidInitialEnv PATH "C:/sqlite3_ext;${PHPROOT};%PATH%"
```

## 7. 安裝與 rollback

先備份，再覆蓋；範例的時間戳請依實際時間調整：

```bat
copy C:\ms4w_MSSQL\Apache\php\ext\php_sqlite3.dll C:\ms4w_MSSQL\Apache\php\ext\php_sqlite3.dll.backup-YYYYMMDD-HHMM
copy /Y C:\php-sdk\phpmaster\vs16\x64\php-8.3.32\x64\Release_TS\php_sqlite3.dll C:\ms4w_MSSQL\Apache\php\ext\php_sqlite3.dll

C:\ms4w_MSSQL\Apache\bin\httpd.exe -t
C:\ms4w_MSSQL\Apache\bin\httpd.exe -k restart -n "ApacheMS4WMSSQLWebServer:port82"
```

若隔離驗證、CLI 或實際 FastCGI request 失敗，先把 backup 覆蓋回去，再 restart Apache。不要同時替換未驗證的 PDO 與 SQLite3 DLL，否則難以定位問題。

本次已安裝的 RTree DLL 使用 SQLite 3.46.0；若日後改用其他 SQLite deps library，應重新做 RTree、SpatiaLite 與實際 Easymap endpoint 的回歸驗證。

## 常見錯誤

| 現象 | 原因與處理 |
|---|---|
| `no such module: rtree` | `php_sqlite3.dll` 沒含 RTree，或 Web process 尚未重啟；先執行第 6 節 probe。 |
| `linked with 14.4x, but the core is linked with 14.29` | 用了 vc17 / VS2022；改用 VS2019 vc16。 |
| `malloc.h: No such file or directory` | `INCLUDE` 沒含 Windows SDK UCRT 目錄；使用第 3 節設定。 |
| `bison is required` 或 `mc is required` | SDK 工具未在 PATH；加入 `C:\php-sdk\msys2\usr\bin` 與 Windows SDK x64 bin。 |
| `not authorized` / 無法 `load_extension()` | 尚未重編 `php_pdo_sqlite.dll` 的第 4.1 節 patch，或 FastCGI PATH 沒有 `C:\sqlite3_ext`。 |
