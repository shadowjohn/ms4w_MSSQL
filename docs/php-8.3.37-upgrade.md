# PHP 8.3.37 更新與 SQLite GIS 重編

日期：2026-11-20。本機由 PHP Windows 8.3.36-1 更新至 **8.3.37 TS x64 VS16**。本次保留 PHP 8.3 分支與 API20230831 ABI，不變更 Apache、IIS 設定或 SQLSRV driver。本次更新納入 v2026.11.20。

## 更新範圍

- 官方 Windows PHP runtime 與配套 DLL，依既有 `PHP_RUNTIME.json` 管理 81 個檔案；其中 61 檔有差異。
- `php_pdo_sqlite.dll`、`php_sqlite3.dll` 以 PHP 8.3.37 原始碼與同版本 development pack 重編，靜態 SQLite 維持 3.54.1，保留 PDO `load_extension()`、open_basedir authorizer 與 RTree。
- PHP 內的 zlib 更新至 1.4；curl 8.23.0、Brotli 1.2.1、libzip 1.12.1 保留官方套件提供的版本。
- 保留原 `php.ini`、OpenSSL 設定、CA bundle、SQLSRV/PDO_SQLSRV 5.12.0、app-local VC DLL 與本機 GIS 相依檔。原本未管理的 Oracle extensions 沒有額外加入。
- `scripts/Build-PhpSqliteExtensions.ps1` 新增 `-PhpVersion`，限制 PHP 8.3 patch 版本，並核對 source／devel headers 完全一致；不傳參數時保留原 8.3.36 預設行為。

[PHP 官方 changelog](https://www.php.net/ChangeLog-8.php#8.3.37)列出 CGI PATH_INFO、Date timezone cache、Session、Phar、SOAP、Streams 等安全修補。PHP-FPM 的修補也列在同一版公告，但不代表本 Windows Apache FastCGI 部署使用 FPM。未執行惡意 exploit PoC，不宣稱全部環境已完成漏洞驗收。

## 官方輸入

| 輸入 | SHA-256 |
| --- | --- |
| [PHP Windows TS x64 VS16 ZIP](https://downloads.php.net/~windows/releases/php-8.3.37-Win32-vs16-x64.zip) | 07984bdcfd4391888954c2e73b1cf2c0d403cfa5fd8cb32ad60ddcd854c6b7de |
| [PHP 8.3.37 source](https://downloads.php.net/~windows/releases/php-8.3.37-src.zip) | 10dbc26beedd10c039f8a4232183166161aa93a9f49a8eac2e0a23cfb0ef3691 |
| [PHP 8.3.37 development pack](https://downloads.php.net/~windows/releases/php-devel-pack-8.3.37-Win32-vs16-x64.zip) | 8f75d8a9be8eb75701951eb91b420664e1372c862c6212129d59d58480250901 |

上述雜湊與[官方 Windows release index](https://downloads.php.net/~windows/releases/releases.json)相符。SQLite 延用[3.54.1 官方 amalgamation](https://www.sqlite.org/2026/sqlite-amalgamation-3540100.zip)，ZIP SHA3-256 為 `92281c86e2957f9b9305890f9ac04204caa7b677cc868dc326d942689df28e30`。PHP ZIP 內的 SBOM 是上游基底；自製 extension 的實際版本以 `PHP_RUNTIME.json.customExtensions` 及 `files` 雜湊為準。

## 可重現重編

使用 VS2019 14.29 x64 工具、Windows SDK 10.0.26100.0，以及以上驗證過的輸入：

```powershell
./scripts/Build-PhpSqliteExtensions.ps1 `
  -PhpVersion 8.3.37 `
  -PhpSource '<PHP 8.3.37 source root>' `
  -PhpDevel '<PHP 8.3.37 TS x64 VS16 development root>' `
  -SqliteSource '<sqlite-amalgamation-3540100>' `
  -CompilerRoot '<VS2019 VC/Tools/MSVC/14.29.x>' `
  -OutputDirectory '<new build directory>'
```

本機編譯器為 MSVC 19.29.30159。此次自製 DLL：

- `php_pdo_sqlite.dll`：`ffc17fedc91fcb294c0dedb6c425f04db119ea5bd909436cd447486b1c9b6c40`
- `php_sqlite3.dll`：`3eb0e0aebb37c84b8f5657ce85fc4ef9430ef67d045fbd8e9f936a7329c9a213`

兩個 extension 均回報 8.3.37，SQLite engine 為 3.54.1。產物維持 NotSigned；重編時間戳可能造成下一次產物雜湊不同。以 8.3.37 source 搭配預設 8.3.36 要求的負向驗證會在建立輸出前拒絕，避免混用 source／SDK。

## 其他主機套用與回復

1. 比對目標 PHP 版本／ABI與客製設定，備份待替換檔案及原 `PHP_RUNTIME.json`。
2. 停止使用同份 PHP 的對應 IIS 集區、Apache、CLI worker 與會重啟 PHP 的排程。確認整份更新清單可寫，再開始替換，不逐檔強制解鎖或修改 ACL。
3. 同步 PHP 管理清單內的有差異檔案，以及新的 `PHP_RUNTIME.json`。本次不需要更新 Apache/bin、Apache/modules、CGI 或 VC runtime。保留主機設定、憑證、SQLSRV、GIS 額外 DLL，勿直接用官方 ZIP 蓋掉自製 SQLite extensions。
4. 執行 `scripts/Test-Runtime.ps1`、`httpd -t`，再透過實際 Web SAPI 驗證 PHP 8.3.37、自製 extensions、RTree、SpatiaLite 與應用程式功能。
5. 恢復對應服務／worker，驗證實際網站與 DB。若失敗，停止相關程序後回復完整備份及原清冊，確認一致後才恢復服務。

## 驗證與邊界

候選 CLI 10/10、Web 16/16、記憶體 GIS 27/27 通過。包含 PHP ABI／SQLSRV 載入、RTree／SpatiaLite 幾何與索引、缺失 extension 失敗、ZIP／gzip 有效與損壞資料、保留 CA 的 HTTPS、ICU／Enchant 初始化、隔離 Session roundtrip，以及 Apache HTTP/2、Brotli、FastCGI、MapServer CGI 初始化、ModSecurity 放行／阻擋、X-Sendfile 與 404。CLI 模組清單與原設定一致；Intl／Enchant 只在測試命令額外載入，沒有改動 php.ini。

套用後 runtime 8/8、Web 16/16、記憶體 GIS 27/27 通過，81 項 PHP payload 雜湊符合；25 個設定／VC／SQLSRV／未追蹤 GIS 檔案維持原雜湊。備份與本機驗證證據保存在已忽略的 `artifacts/php-8.3.37-2026-11-20/`。

IIS／PHP 由使用者自行停止，本次未操作其啟停或排程設定。沒有連線真實 MSSQL，也未驗收其他主機、IIS 或 production；v2026.11.13 保持原版。

## 防護軟體執行限制

完成上述本機測試後，Apex One 對 php.exe 回報「新發現程式」並拒絕執行。已核對目前 EXE 與官方 ZIP 內檔案逐位元一致，且 EXE／ZIP 均沒有 Zone.Identifier；沒有因此修改防護政策或程式名稱。本機目前可否執行仍取決於管理端政策，不能由先前測試結果推論已解除阻擋。本次發布時的執行驗證交由 GitHub Windows runner，公開下載包另核對來源 commit 與 payload SHA-256。此限制與其他主機實際允許情況分開記錄。
