# PHP 8.3.36 安全升級與其他主機更新

這次保留 PHP 8.3 分支、x64、TS/ZTS、VS16 ABI，更新官方 Windows runtime 與配套 DLL，修補 CVE-2026-109618／CVE-2026-109619。編好的檔案已隨 repo 簽入，更新主機不需要重新編譯。

## 隨 repo 提供的版本

| 元件 | 版本／處理 |
|---|---|
| PHP / Zend OPcache | 8.3.36 x64 TS VS16 |
| php_pdo_sqlite.dll、php_sqlite3.dll | 以官方 PHP 8.3.36 原始碼重建，靜態 SQLite 3.54.1 |
| SQLite GIS 功能 | 保留 PDO load_extension()、RTree；既有 SpatiaLite 5.1.0 依賴不變 |
| SQLSRV / PDO_SQLSRV | 保留已驗證的 5.12.0、PHP 8.3 TS x64 DLL |
| Apache、app-local VC runtime | 不變；VC manifest 沿用原版 |
| php.ini、Apache 設定、憑證 | 保留，未納入這次設定變更 |

官方原始 SQLite extensions 無法保留此工具需要的 PDO SpatiaLite 載入與 RTree，因此簽入的是已驗證的自訂重建檔，不可改回官方原始兩個 DLL。自訂 DLL 靜態連結新的 SQLite，不依賴舊 libsqlite3.dll；其他官方 runtime DLL 一併更新，避免混搭。官方 SBOM 是上游 ZIP 的資料；自訂兩個 extension 的實際內容、來源與雜湊以 `ms4w_MSSQL/PHP_RUNTIME.json` 為準。

## 來源與可重現建置

版本公告：https://www.php.net/archive/2026.php 。Windows SHA-256：https://downloads.php.net/~windows/releases/releases.json 。建置說明：https://wiki.php.net/internals/windows/stepbystepbuild_sdk_2 。RTree：https://www.sqlite.org/rtree.html 。

| 官方輸入 | 雜湊 |
|---|---|
| https://downloads.php.net/~windows/releases/php-8.3.36-Win32-vs16-x64.zip | SHA-256 `0606810ff8fc232406aaab677b760e06af93a63a366d33ff738d4ce90501dfa5` |
| https://downloads.php.net/~windows/releases/php-8.3.36-src.zip | SHA-256 `2dd2271952dff11ec1f7149ef0cc661132c918ae2a419e1842b31defaf5007e8` |
| https://downloads.php.net/~windows/releases/php-devel-pack-8.3.36-Win32-vs16-x64.zip | SHA-256 `6d4b58f6baf0e72e3d13fc5d613a01ef6af0a85864df5033c236bbd515668fb5` |
| https://www.sqlite.org/2026/sqlite-amalgamation-3540100.zip | SHA3-256 `92281c86e2957f9b9305890f9ac04204caa7b677cc868dc326d942689df28e30` |

如需重建，先驗證上述官方來源並解壓，使用 VS2019 14.29 x64 工具及 Windows SDK；PHP development package 必須是 8.3.36 TS x64 VS16。執行：

```powershell
./scripts/Build-PhpSqliteExtensions.ps1 `
  -PhpSource '<解壓後的 PHP 原始碼目錄>' `
  -PhpDevel '<php-8.3.36-devel-vs16-x64 目錄>' `
  -SqliteSource '<sqlite-amalgamation-3540100 目錄>' `
  -CompilerRoot '<VS2019 VC/Tools/MSVC/14.29.x 目錄>' `
  -OutputDirectory '<全新的建置輸出目錄>'
```

腳本在 source 副本套用既有 PDO patch：成功開庫後呼叫 `sqlite3_enable_load_extension(H->db, 1)`；保留 open_basedir authorizer。SQLite 啟用 RTree、column metadata、threadsafe、FTS3/4/5 與 math functions。腳本只建置輸出，不會部署或重啟服務。這是本工具既有可信任應用程式的載入行為，不要把不受信任 SQL 直接交給這種連線。

產物為本機從官方來源重建，沒有新增 Authenticode 簽章或檔案版本資源；PHP module 版本為 8.3.36。編譯時間戳可能使重新建置的 SHA-256 不同，簽入且驗證的產物雜湊是：

- `php_pdo_sqlite.dll`：`8a4c4e1ed436c14d64e5162f9e45b3eff0d507ddcb9aec3c70efe5c8806f0666`
- `php_sqlite3.dll`：`daa0b03b59471bce36448e9005ebc9b6bca83c5b1ccc344ea6652db8e06ec4ef`

## 其他主機更新順序

1. 確認本機修改與遠端版本，備份完整 PHP、Apache 設定及 SQLite/SpatiaLite 依賴；不要覆蓋站台資料、原 php.ini 或帳密。此 repo 的 runtime binary 原本即由 Git 追蹤，請整套同步，不要只複製 php.exe 或單一 DLL。
2. 盤點所有共用此 PHP 的程序。AIHub 的 Windows 登入排程可能只是啟動 WSL `aihub-wsl-worker.service`，停排程不會停止已運行的 worker；應先讓執行中任務結束，再暫停實際 worker。IIS FastCGI、其他 Apache 或 CLI 也可能載入同一路徑；僅停止已確認的對應站台／app pool／worker，不要停止整個 IIS、WSL 或全機 PHP。
3. 以管理員權限停止 MS4W 工具服務，確認目標 PHP DLL 已釋放。不要在 runtime 運作時執行會覆寫其 binary 的 git pull；鎖檔／未知變更時停止，不修改 ACL、不刪保護、不刷新備份基準。
4. 在已備份且乾淨的 repo 正常 `git pull --ff-only origin main`，保留原主機設定。核對 `PHP_RUNTIME.json` 的部署檔 SHA-256、確認 `php.ini` 啟用 pdo_sqlite、sqlite3、sqlsrv 與 pdo_sqlsrv，保留 SpatiaLite 的依賴搜尋路徑。
5. 執行 `scripts/Test-Runtime.ps1`、`httpd -t`。再以新建臨時 SQLite 庫驗證 SQLite3/PDO CRUD、RTree 建表與查詢、PDO load_extension()、SpatiaLite 幾何與空間索引新增／讀取／更新／刪除；只看 SQLite 基本 CRUD 或 compile_options 不足以驗證 GIS。
6. 啟動 MS4W，透過該主機實際 Web SAPI 驗證 PHP 8.3.36、正確 ini、全部 PDO driver、SQLSRV/PDO_SQLSRV 載入與上述臨時 GIS 測試；清除測試 probe。最後恢復原本運行的 worker，讓使用者自行恢復手動停用的排程。若部署失敗，只回復實際變更且可驗證的檔案；回復不完整時不啟動混用 runtime。

## 此次驗證

CLI 與實際 port 82 Apache FastCGI 均為 PHP 8.3.36；HTTP 200、SAPI cgi-fcgi、SQLite 3.54.1、SpatiaLite 5.1.0，全部上述 GIS 檢查通過。SQLSRV/PDO_SQLSRV 5.12.0 載入，PDO drivers mysql/odbc/pgsql/sqlite/sqlsrv 可用。81 個部署檔雜湊吻合，原 ini／Apache 設定保持，Apache Syntax OK，臨時 probe 清除後回覆 404，AIHub worker 恢復 active/running。

未連線或修改真實 MSSQL 資料庫；未操作其他主機。應用程式真實資料與其他主機環境仍需由各主機正常驗證。舊 PHP 5.3.2 legacy CGI 是另一組相容性範圍，此次沒有升級，請勿把主 PHP 升級視為所有 legacy CGI 都已修補。
