# Tehdit modeli (STRIDE) — Nova MVP

Varlıklar: kullanıcının kaynak kodu ve dosyaları, Claude Code oturumu (CLI'ın kimliği), shell erişimi, transcript'ler.
Güven sınırları: **(A)** Nova ↔ `claude` alt süreci (stdin/stdout), **(B)** model çıktısı → Nova UI, **(C)** Nova ↔ dosya sistemi.

| # | Tehdit (STRIDE) | Sınır | Kontrol | Kod / test |
|---|---|---|---|---|
| T-1 | **Tampering/EoP:** kullanıcı metni veya klasör adı shell'e enjekte edilir | A | Shell yok; `Process.arguments`; kullanıcı metni yalnızca stdin JSON | `LaunchConfiguration`, `ClaudeProcess`; `userTextNeverInArguments`, `encodesUserMessageAsSingleLine` |
| T-2 | **Spoofing:** sahte `claude` çalıştırılabilir | C | Bilinen yollar → sabit login-shell sorgusu; Ayarlar'da yol görünür; sürüm gösterilir | `CLILocator` |
| T-3 | **EoP/Info disclosure:** model çıktısındaki SVG/HTML JS çalıştırır, ağa veya file://'a erişir | B | CSP `default-src 'none'`, etiket/öznitelik ayıklama, JS kapalı, nonPersistent, baseURL yok, gezinme reddi | `WidgetDocument`, `SandboxedWebView`; `stripsActiveContent` |
| T-4 | **EoP:** Full access (bypassPermissions) kazara açılır | A | Kırmızı rozet; ilk kullanımda onay diyaloğu; sohbet modunda imkânsız (her zaman `default` + salt-okunur araçlar) | `PermissionModeMenu`, `NewSessionSheet`; `chatModeIsReadOnly` |
| T-5 | **Tampering:** izin kartında yanlışlıkla onay | B | Düz ↩ atanmadı; ⌘↩ / ⌥⌘↩ / ⌘⌫; kart araç adı + komut/diff önizlemesi gösterir | `PermissionCard` |
| T-6 | **Info disclosure:** loglarda prompt/dosya içeriği | — | `os.Logger` yalnızca meta veri (mod, araç adı, karar, süre); stderr kullanıcıya gösterilir, loglanmaz | `AgentEngine`, `SessionController` |
| T-7 | **DoS:** dev/bozuk stdout satırı belleği tüketir | A | Satır üst sınırı 64 MB, bozuk satır atlanır; uzun çıktılar UI'da kırpılır; vurgulama 60 KB sınırı | `NDJSONLineSplitter`, `ToolCallBody.clip` |
| T-8 | **Repudiation/Integrity:** Nova CLI geçmişini bozar | C | Geçmiş salt-okunur; Nova session silse de JSONL'a dokunmaz | `HistoryIndexer`, `AppModel.delete` |
| T-9 | **DoS:** ölmüş sürecin stdin'ine yazmak SIGPIPE ile uygulamayı düşürür | A | `SIGPIPE` yok sayılır; yazma hata döndürür, UI'da gösterilir | `ClaudeProcess` |
| T-10 | **Yetim süreçler** | A | Çıkışta `applicationShouldTerminate` → tüm süreçlere SIGTERM, 2 sn sonra SIGKILL | `AppDelegate`, `ClaudeProcess.terminate` |

Kalan riskler: Kod modunda CLI'ın kendisi kullanıcının yetkileriyle çalışır (tasarım gereği; izin modları CLI tarafından
uygulanır). Abonelik koşulları için G1 kontrolü PROJECT_STATE'te açık madde olarak durur.
