# Apache 2.4.71 與 PHP 8.3.36-1 更新及上架清單

日期：2026-11-13。此文件記錄本次 runtime 更新來源、部署範圍與驗證邊界。

本次更新納入 v2026.11.13；下方驗證結果以本機與隔離環境為範圍，其他主機仍需實際驗收。

## 更新內容

| 元件 | 原版本 | 更新目標 | 範圍 |
| --- | --- | --- | --- |
| Apache | 2.4.69 | 2.4.71 Win64 VS18，2026-11-11 build | 官方 bin、modules，保留 MS4W 額外檔案 |
| Apache curl | 8.22.0 | 8.23.0 | curl.exe、libcurl 與同包相依 DLL |
| nghttp2 | 1.70.0 | 1.71.0 | Apache bin |
| Apache zlib | 1.3.2 | 1.4 | 新增 libz.dll；保留舊 GIS 所需 z.dll |
| ModSecurity | 2.7.0-rc2 | 2.9.15 VS18 | mod_security2.so、bin/yajl.dll，保留原本未啟用狀態 |
| mod_fcgid | 2.3.10-dev VS17 build | 2.3.10 VS18 build | 原本已啟用的 FastCGI 模組 |
| mod_xsendfile | 原有舊 build | 1.0-P1 VS18 | 更新既有模組，保留原本未啟用狀態 |
| PHP | 8.3.36 + Brotli overlay | 官方 Windows 8.3.36-1 重建包 | 56 個有差異的已管理檔案；php -v 仍顯示 8.3.36 |
| VC++ app-local runtime | 14.51.36247.0 | 14.52.37029.0 x64/x86 | bin、php、cgi-bin 內原本隨附的 VC DLL |

Apache OpenSSL 3.5.9、Brotli 1.2.1 維持原版本，改由新 Apache 官方包原生提供。PHP -1 包補齊 glib 2.90.1、libzip 1.12.1 與 zlib 安全回補；不能只憑 PHP 的版本字串判斷是否更新。PHP 自製 SQLite 3.54.1、SQLSRV 5.12.0、php.ini、OpenSSL 設定及 CA bundle 保留。

[Apache 官方安全公告](https://httpd.apache.org/security/vulnerabilities_24.html)列出 2.4.71 修補 CVE-2026-119618（mod_http2 heap corruption/RCE）、CVE-2026-106023（mod_md crash）與 CVE-2026-109163（mod_vhost_alias stack overwrite）。是否實際暴露仍取決於各主機啟用的模組與設定；本機原設定未啟用 mod_http2。隔離測試臨時啟用 HTTP/2，沒有更改正式設定。

## 上架是否只需 Apache/bin 與 Apache/modules

**僅更新 Apache 本體時，主要二進位範圍確實是這兩個目錄；本次包含 PHP 與 VC runtime，因此完整更新需要下表範圍。**

以下路徑以實際 MS4W runtime 根目錄為基準，例如 C:/ms4w_MSSQL，並非外層 Git repository。

| 路徑 | 此次需部署的內容 |
| --- | --- |
| Apache/bin/ | 新 Apache 官方 bin 全部對應檔案、mod_security 所需 yajl.dll、3 個 x64 VC DLL；務必包含新增 libz.dll |
| Apache/modules/ | 新 Apache 標準模組與 3 個額外模組，採覆蓋對應檔案，不刪除其他模組 |
| Apache/php/ | PHP_RUNTIME.json 的 PHP payload 清單與 VC_RUNTIME_X64.json 的 3 個 DLL，包含 ext、extras/sbom 等有變更的子目錄 |
| Apache/cgi-bin/ | 僅 vcruntime140.dll、msvcp140.dll 兩個 x86 VC DLL |
| Apache/LICENSE.txt、NOTICE.txt、licenses/ | 對應這次 Apache、mod_fcgid、ModSecurity/YAJL、mod_xsendfile 的授權及聲明 |
| APACHE_RUNTIME.json、PHP_RUNTIME.json、VC_RUNTIME_X64.json、VC_RUNTIME_X86.json | 來源、版本、完整性清冊，需與部署檔一起更新 |

不要用官方 Apache ZIP 整包覆蓋 MS4W，也不要以鏡像同步刪除 bin/modules 的額外檔案。PHP 亦不可直接整包覆蓋：會蓋掉自製 php_pdo_sqlite.dll、php_sqlite3.dll 與本機設定。各主機需保留原有 httpd.conf、conf/extra、httpd.d、php.ini、憑證、htdocs、CGI、SQLSRV 與 GIS 依賴。

若目標主機版本不同於本次基線，先比較清冊及自製 extension ABI；不能假定只複製本次差異就等於完成更早版本的升級。只部署 Apache 時，也必須確認該主機的 VC runtime 至少符合本版 14.52.37029 要求；app-local 舊 DLL 不能靠安裝系統新版來掩蓋。

## 部署順序與回復

1. 確認來源／目標、現有版本與設定差異，備份會被替換的檔案及對應清冊。
2. 停止目標 Apache，以及共用 Apache/php 的測試站、IIS worker、排程或背景工作。若 PHP 持續重生，需先定位真正的啟動來源；不要逐一強殺程序或對運行中的 DLL 做覆寫。
3. 確認完整更新清單皆可寫，再同步上述對應檔案。保留自製 SQLite、SQLSRV、站台設定與資料。
4. 核對四份 runtime JSON 的 SHA-256，執行 scripts/Test-Runtime.ps1、httpd -t，再驗證該主機實際 Web SAPI、HTTPS/HTTP2、FastCGI、GIS 與所用資料庫。
5. 啟動原本需要運行的服務／worker，確認實際版本及行為。若失敗，停止對應程序後回復完整原檔與原清冊，確認一致再啟動。

## 來源與完整性

| 套件 | 來源 | SHA-256 |
| --- | --- | --- |
| Apache 2.4.71 | [Apache Lounge](https://www.apachelounge.com/download/VS18/binaries/httpd-2.4.71-261112-Win64-VS18.zip) | 44961a929dff16b767b3adbcea55760a942a00239b2891dc55806be34029e1fc |
| PHP 8.3.36-1 TS x64 VS16 | [PHP Windows](https://downloads.php.net/~windows/releases/php-8.3.36-1-Win32-vs16-x64.zip) | 126dd3cc8c19df5085b9420b2bc74ed591de3d98528858c52fc42739b7bba92e |
| Microsoft VC x64 | [Microsoft](https://aka.ms/vc14/vc_redist.x64.exe) | 9c02c9ed120f671b900e6b9471d890e3b2414117a7e53f4ae2e855466fa2b7c9 |
| Microsoft VC x86 | [Microsoft](https://aka.ms/vc14/vc_redist.x86.exe) | 7b0117e6e20e9e349029c000a8a2715a52cf37c15b6bb697b2908e8bc7066cdf |

Apache hash 與[供應商 checksum](https://www.apachelounge.com/download/VS18/binaries/httpd-2.4.71-261112-Win64-VS18.zip.txt)相符，PHP hash 與[官方 SBOM](https://downloads.php.net/~windows/releases/php-8.3.36-1-Win32-vs16-x64.zip.spdx.json)相符。VC 來源 EXE 與萃取後 DLL 的 Authenticode 均為 Valid，版本／架構符合；未執行 redistributable 安裝程式。額外模組從 Apache Lounge HTTPS 下載，逐包計算 hash；下載頁沒有提供可公開交叉驗證的 checksum，不能稱為已核對供應商簽章。Apache 與 PHP 執行檔仍無 Authenticode 簽章。

## 已驗證與保留項目

候選 CLI 8/8；套用後 runtime 8/8、隔離 Web 16/16、記憶體 GIS 27/27 及 Apache/PHP/VC 全部 279 個清冊項目的 SHA-256 通過，35 個保護檔案保持原 hash。包含 TLS HTTP/2 實際協商、平行請求、Brotli 解壓完整性、PHP FastCGI、SQLSRV 載入、SQLite RTree、PDO SpatiaLite、MapServer CGI 初始化、ModSecurity 放行／403 阻擋、X-Sendfile、404 與無 PHP error log。CLI 另外驗證 ZIP/gzip 有效及損壞輸入、GIS 幾何／索引與保留 CA 的外部 HTTPS。未使用 CVE exploit PoC，不能宣稱已做惡意漏洞重現。

下列升級另有相容性範圍，未混入這次 runtime 替換：

- SQLSRV 最新 5.13.3；目前保留 5.12.0。新分支有安全／正確性修補，也移除部分 OS/SQL Server 支援，需先確認實際 Windows、SQL Server 版本並做 DB 回歸。[Microsoft release notes](https://learn.microsoft.com/en-us/sql/connect/php/release-notes-php-sql-driver?view=sql-server-ver17)、[support matrix](https://learn.microsoft.com/en-us/sql/connect/php/microsoft-php-drivers-for-sql-server-support-matrix?view=sql-server-ver17)。
- Python 3.7.8 已 EOL；GDAL 2.4.0、MapServer 7.7.0-dev 與 legacy GIS DLL 也需整套遷移及地圖／資料驗收，不能直接以最新 EXE 或 DLL 覆蓋。[Python 官方狀態](https://www.python.org/downloads/release/python-378/)。
- 沒有連線真實 MSSQL，沒有驗證其他主機、IIS 或 production，也沒有修改部署主機與發布 GitHub Release。
