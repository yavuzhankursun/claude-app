# Tehdit modeli (STRIDE) — Monster MVP

Varlıklar: kullanıcının kaynak kodu ve dosyaları, Claude Code oturumu (CLI'ın kimliği), shell erişimi, transcript'ler.
Güven sınırları: **(A)** Monster ↔ `claude` alt süreci (stdin/stdout), **(B)** model çıktısı → Monster UI, **(C)** Monster ↔ dosya sistemi.

| # | Tehdit (STRIDE) | Sınır | Kontrol | Kod / test |
|---|---|---|---|---|
| T-1 | **Tampering/EoP:** kullanıcı metni veya klasör adı shell'e enjekte edilir | A | Shell yok; `Process.arguments`; kullanıcı metni yalnızca stdin JSON | `LaunchConfiguration`, `ClaudeProcess`; `userTextNeverInArguments`, `encodesUserMessageAsSingleLine` |
| T-2 | **Spoofing:** sahte `claude` çalıştırılabilir | C | Bilinen yollar → sabit login-shell sorgusu; Ayarlar'da yol görünür; sürüm gösterilir | `CLILocator` |
| T-3 | **EoP/Info disclosure:** model çıktısındaki SVG/HTML JS çalıştırır, ağa veya file://'a erişir | B | CSP `default-src 'none'`, etiket/öznitelik ayıklama, JS kapalı, nonPersistent, baseURL yok, gezinme reddi | `WidgetDocument`, `SandboxedWebView`; `stripsActiveContent` |
| T-4 | **EoP:** Full access (bypassPermissions) kazara açılır | A | Kırmızı rozet; ilk kullanımda onay diyaloğu; sohbet modunda imkânsız (her zaman `default` + salt-okunur araçlar) | `PermissionModeMenu`, `NewSessionSheet`; `chatModeIsReadOnly` |
| T-5 | **Tampering:** izin kartında yanlışlıkla onay | B | Düz ↩ atanmadı; ⌘↩ / ⌥⌘↩ / ⌘⌫; kart araç adı + komut/diff önizlemesi gösterir | `PermissionCard` |
| T-6 | **Info disclosure:** loglarda prompt/dosya içeriği | — | `os.Logger` yalnızca meta veri (mod, araç adı, karar, süre); stderr kullanıcıya gösterilir, loglanmaz | `AgentEngine`, `SessionController` |
| T-7 | **DoS:** dev/bozuk stdout satırı belleği tüketir | A | Satır üst sınırı 64 MB, bozuk satır atlanır; uzun çıktılar UI'da kırpılır; vurgulama 60 KB sınırı | `NDJSONLineSplitter`, `ToolCallBody.clip` |
| T-8 | **Repudiation/Integrity:** Monster CLI geçmişini bozar | C | Geçmiş salt-okunur; Monster session silse de JSONL'a dokunmaz | `HistoryIndexer`, `AppModel.delete` |
| T-9 | **DoS:** ölmüş sürecin stdin'ine yazmak SIGPIPE ile uygulamayı düşürür | A | `SIGPIPE` yok sayılır; yazma hata döndürür, UI'da gösterilir | `ClaudeProcess` |
| T-11 | **Info disclosure / path traversal:** yazılan `@yol` proje dışındaki bir dosyayı (`../`, mutlak yol, dışarıyı gösteren sembolik bağ) modele gönderir | C | Yol köke göre çözülür, sembolik bağlar açılır, kök dışındaysa reddedilir ve kullanıcıya uyarı gösterilir; okuma `O_NOFOLLOW` + `F_GETPATH` ile kökün `realpath`'ine karşı yeniden denetlenir (kontrol–okuma arası değişime karşı); yalnızca kod modunda | `MentionResolver`, `SafeFile`; `rejectsMentionsOutsideRoot` |
| T-12 | **DoS / maliyet:** dev ek ya da çok sayıda bahsetme | C | Satır içi metin ≤ 256 KB ve NUL'suz UTF-8, aksi halde yalnızca yol; görsel ≤ 5 MB ve türü ilk baytlardan (uzantı değil); okuma `maxBytes + 1` ile sınırlı; FIFO/aygıt dosyası reddedilir (`O_NONBLOCK` + `S_ISREG`, ana thread kilitlenmez); en fazla 10 ek, 20 bahsetme | `Attachment.load`, `MentionResolver`, `SafeFile`; `oversizedImageIsRejected`, `imageTypeIsSniffedFromBytesNotExtension`, `largeOrBinaryMentionsBecomeReferences`, `specialFilesAreRefusedWithoutBlocking`, `inlineReadIsBounded` |
| T-13 | **Tampering:** ⌘V yakalayıcı metin yapıştırmayı bozar ya da başka pencerelerde çalışır | — | Yalnızca composer odaktayken ve yalnızca kendi penceresinden gelen olaylarda; panoda metin varsa dokunmaz, olayı geçirir | `PasteInterceptor` (elle doğrulandı: metin ve görsel yapıştırma) |
| T-14 | **Spoofing (istem):** satır içi dosyadaki `</file>` etiketi kapatıp sonrasını kullanıcı metni gibi gösterir | B | İçerik, içinde geçmeyen rastgele bir sınırlayıcıyla sarılır; yoldaki `"`, `\` ve satır sonu kaçırılır | `UserMessage.fileText`; `inlinedFileCannotCloseItsOwnDelimiter` |
| T-10 | **Yetim süreçler** | A | Çıkışta `applicationShouldTerminate` → tüm süreçlere SIGTERM, 2 sn sonra SIGKILL | `AppDelegate`, `ClaudeProcess.terminate` |

Kalan riskler: Sabit bağlar (hard link) yol çözümlemesiyle ayırt edilemez; proje içindeki bir sabit bağ kök dışındaki dosyanın
içeriğini `@` ile ekleyebilir (kabul edildi: sabit bağı oluşturmak zaten o dosyaya yazma yetkisi ister). Proje kökü `/` ya da `~` seçilirse
`@` her yere erişir (kullanıcının seçimi). Tek mesaj en kötü ~75 MB (10 × 5 MB base64 görsel + metin) olabilir; pipe'a eşzamanlı yazılır.
 Kod modunda CLI'ın kendisi kullanıcının yetkileriyle çalışır (tasarım gereği; izin modları CLI tarafından
uygulanır). Abonelik koşulları için G1 kontrolü PROJECT_STATE'te açık madde olarak durur.
