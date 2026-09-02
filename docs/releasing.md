# Release 發布方式

這個 repo 保存的是一整套 Windows runtime，不是從原始碼即時編譯的應用程式。Release 會從指定 commit 打包 Git 已追蹤的 runtime，產生 ZIP、SHA-256 與檢查清單，再把 ZIP 解壓後重新執行核心工具。

## 版本命名

MS4W 基底版本與 Apache、PHP 等 runtime 的更新時間不一定相同，因此 tag 採日期版本：

```text
vYYYY.MM.DD
```

同一天若需要補發，可在後面加流水號，例如 `v2026.07.20.1`。版本說明放在 `docs/releases/<tag>.md`。

## 本機檢查

```powershell
./scripts/Test-Runtime.ps1
./scripts/New-ReleasePackage.ps1 -ReleaseTag v2026.07.20
./scripts/Test-ReleasePackage.ps1 `
  -PackagePath ./artifacts/ms4w_MSSQL-v2026.07.20-windows-x64.zip `
  -ChecksumPath ./artifacts/SHA256SUMS.txt `
  -ManifestPath ./artifacts/release-manifest.json
```

要保留解壓內容供人工檢查時，可加上 `-KeepExtracted`。GitHub Actions 會使用這個選項，工作結束後由一次性的 runner 統一回收，避免發版前花時間逐檔刪除約一萬個暫存檔。

打包腳本只會收錄 Git 已追蹤的檔案，並排除 `ms4w_MSSQL/tmp` 內的 URL cache 圖片。Apache log、PHP error log、本機上傳資料、私有設定與帳密都不應進入版控或 Release。

`ms4w_MSSQL/VC_RUNTIME_X64.json` 與 `ms4w_MSSQL/VC_RUNTIME_X86.json` 定義隨 ZIP 提供的 app-local Microsoft Visual C++ v14 runtime。Apache、PHP 是 x64，MapServer 與 legacy CGI 是 x86；同一目錄不能混放不同架構、同名的 runtime DLL。`Test-Runtime.ps1` 會在執行任何 runtime EXE 前，確認 DLL 的版本與 SHA-256、PE 架構與對應清單一致，並從 PE import table 驗證入口程式仍需要 `VCRUNTIME140.dll`。更新 runtime 時，必須從 Microsoft 已驗證的對應架構 redistributable 來源取得可轉散發檔案，同步更新 JSON 清單與部署目錄；不得從任意機器的 `System32` 或第三方 DLL 站直接取檔。

## 發布步驟

1. 更新 README 內的元件版本，並新增 `docs/releases/<tag>.md`。
2. 執行完整的本機檢查。
3. 只 stage 這次調整的檔案，確認 diff 後以繁體中文提交。
4. push 前先執行 `git pull --rebase origin main`，有遠端變更就先整合並重跑檢查。
5. push `main` 後，再執行 `git pull --ff-only origin main` 確認同步。
6. 建立 annotated tag，push tag 前再執行一次 `git pull --ff-only origin main`。

```powershell
git tag -a v2026.07.20 -m "release: 發布 2026-07-20 Windows runtime"
git push origin v2026.07.20
```

tag push 後，GitHub Actions 會建立或更新同名 Release。也可以從 Actions 手動執行 workflow，但輸入的 tag 必須已存在。

## 公開後驗證

不能只看 workflow 綠燈。Release 建立完成後，應重新下載三個資產，再核對 SHA-256 與解壓後 smoke check：

```powershell
gh release download v2026.07.20 -R shadowjohn/ms4w_MSSQL -D ./artifacts/downloaded
./scripts/Test-ReleasePackage.ps1 `
  -PackagePath ./artifacts/downloaded/ms4w_MSSQL-v2026.07.20-windows-x64.zip `
  -ChecksumPath ./artifacts/downloaded/SHA256SUMS.txt `
  -ManifestPath ./artifacts/downloaded/release-manifest.json
```

目前主要執行檔沒有 Authenticode 簽章。Release 說明與 `release-manifest.json` 必須保留實際的 `NotSigned` 狀態，不能寫成已簽章版本。
