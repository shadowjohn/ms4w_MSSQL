# CGI 目錄盤點與跨主機清理

盤點日期：2026-11-05。實體目錄為 `ms4w_MSSQL/Apache/cgi-bin/`，本機 `C:\ms4w_MSSQL` 連結到同一份 runtime。

## 目前狀態

舊 PHP 專用檔案已先清除。建立清理 BAT 前，CGI 頂層剩下 **211 個檔案、344.68 MiB**；`mapscript/` 另有 **30 個檔案、3.46 MiB**。之後使用者已在本機執行清理工具，固定清單中的 25 個路徑目前全部不存在。未追蹤的站台資料不計入上述盤點數字。

目錄除了 MapServer，也混有多代 GDAL、舊 ICU、MapCache、TinyOWS、PDAL、MapScript bindings、建置產生器與測試範例。因此「沒有直接出現在 mapserv.exe 的 imports」不足以判定檔案可以移除。

## 可攜式清理 BAT

檔案：[`remove_cgibin_useless.bat`](../ms4w_MSSQL/Apache/cgi-bin/remove_cgibin_useless.bat)。將這一支 BAT 複製到其他主機的 **Apache/cgi-bin 目錄內** 執行，不需要其他腳本。

- 用 `%~dp0` 定位 BAT 所在目錄，不依賴目前工作目錄，也不寫死磁碟機。
- 旁邊必須有 `mapserv.exe`，且 `../php/php-cgi.exe` 必須存在，才會開始清理。
- 使用固定的 25 個檔名，不做備份、不遞迴刪除。檔案不存在就跳過，可重複執行。
- `printenv.pl`、`test.png` 只有內容符合本次已知樣本的 SHA-256 才會刪除。內容、換行不同或無法核對雜湊時保留。
- 預設執行後暫停顯示結果；`/nopause` 可直接返回。失敗退出碼為 1，位置／參數不符為 2，正常完成為 0。
- 拒絕經 CGI 環境執行。沒有管理員權限時仍可嘗試，但不會強制移除唯讀檔案、修改 ACL 或停止服務；失敗項目會列出。

預覽：

```bat
remove_cgibin_useless.bat /dry-run /nopause
```

直接清理：

```bat
remove_cgibin_useless.bat
```

### 固定清單：17 個舊 PHP 路徑

```text
php.exe
php.ini
php-cgi.exe
php-win.exe
php5apache.dll
php5apache2.dll
php5apache2_2.dll
php5apache2_2_filter.dll
php5apache2_filter.dll
php5apache_hooks.dll
php5embed.lib
php5isapi.dll
php5nsapi.dll
php5pi3web.dll
php5ts.dll
php7embed.lib
php7ts.dll
```

PHP 正式位置是 `Apache/php/`，現有 Apache 設定的 `FcgidWrapper` 也指向該處的 `php-cgi.exe`。

### 固定清單：8 個建置／測試檔案

| 檔案 | 用途 | 本機 bytes |
|---|---|---:|
| `lemon.exe` | SQLite parser 產生器 | 540,160 |
| `mkkeywordhash.exe` | SQLite keyword hash table 產生器 | 444,928 |
| `mksourceid.exe` | SQLite source ID 產生器 | 458,240 |
| `protoc.exe` | Protocol Buffers compiler | 2,520,576 |
| `protoc-gen-c.exe` | Protocol Buffers C code 產生器 | 1,069,568 |
| `gifsample.exe` | OWT GIF 範例程式 | 139,314 |
| `printenv.pl` | CGI 環境變數測試程式，需雜湊相符 | 871 |
| `test.png` | 測試圖片，需雜湊相符 | 24,923 |

共 **5,198,580 bytes，約 4.96 MiB**。這五個建置工具不是 MapServer 執行相依，盤點範圍內未找到追蹤腳本的呼叫；`GDAL/` 的同名 Protocol Buffers 工具不受此 BAT 影響。若主機另外將 CGI 裡的 compiler 當開發工具使用，清理前應調整這份固定清單。

## 保留的 GIS 功能

| 群組 | 保留原因 |
|---|---|
| MapServer 與工具 | `mapserv`、`map2img`、`legend`、`scalebar`、`shapeinfo`、`shptree`、`shptreetst`、`shptreevis`、`sortshp`、`tile4ms`、`msencrypt` |
| MapCache | seed、detail、FastCGI 與相關 module；有隨附設定與使用說明 |
| TinyOWS | WFS／PostGIS 功能，有 `httpd_tinyows.conf` 設定 |
| PDAL | `setenv.bat` 明確將 `PDAL_DRIVER_PATH` 指向 CGI 目錄，plugins 可動態載入 |
| MapScript | C#／Java／Python bindings 可能由外部應用程式使用，30 個檔案共 3.46 MiB |
| OWTChart | `owtchart.exe` 是圖表 CGI，`httpd_owtchart.conf` 有設定，不能當成 GIF sample 一起刪除 |
| 一般 GIS／診斷工具 | OpenJPEG、SQLite、OpenSSL 等 CLI 仍可能經 PATH 使用 |
| `wms.map` | 本機看來是範例，但其他主機可能是實際 MapServer 入口，固定清理清單保留 |

## 大宗待判定 DLL

| 群組 | 檔案數／bytes | 判斷 |
|---|---:|---|
| ICU 38／57／62／63／64／66 | 32／167,287,808，約 159.54 MiB | 最大的待確認群組，不列入跨主機預設清單 |
| GNU／SpatiaLite 群組 | 12／21,188,085 | 其他 SpatiaLite copies 有同名相依，需分清架構、載入位置與動態使用 |
| `FileGDBAPI.dll` | 1／10,154,448 | FileGDB 功能可能動態選用 |
| `NCSEcw.dll` | 1／5,501,464 | ECW 格式可能由 plugin 動態使用 |
| `pdflib.dll` | 1／1,618,432 | 尚未取得足以作跨主機移除的用途證據 |

這次對 **801 個追蹤 PE** 分析一般與 delay imports，沒有解析錯誤。另對 **10,029 個追蹤檔案** 搜尋 ICU 精確檔名的 ASCII／UTF-16LE 引用；98 組命中全部位於 ICU 本身，未找到外部引用。這是 ICU 可繼續縮減的證據，但尚未涵蓋壓縮內容、組合出的 DLL 名稱、外部程式及未追蹤的站台設定。

舊 plugins 仍會引用 `gdal16.dll`、`gdal17.dll`、VC71 與舊 Xerces 等檔案。Python `_tkinter.pyd` 使用 Tcl／Tk，GDAL cURL 使用舊 OpenSSL；不同位置、架構的同名 DLL 也不能只按名字合併或刪除。這些檔案暫時保留。

## 驗證

- 初次工作目錄預覽列出 8 個現存建置／測試候選；使用者後續已在本機實際執行，Git 與檔案檢查確認固定清單的 25 個路徑均已移除。
- 隔離 TEMP fixtures **12/12 通過**：精確清單刪除、GIS／共用 DLL 保留、預覽、錯誤目錄、缺少主 PHP、CGI 環境拒絕、修改樣本保留、重複執行、唯讀檔案失敗、暫停後退出碼。
- 測試從 `System32` 呼叫，路徑包含中文、空白與 `!`，驗證不依賴目前工作目錄。
- 其他主機的真實 DLL 使用者、服務執行與應用程式流程尚未驗收。
