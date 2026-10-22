# PROJECT_STATE

**Son güncelleme:** 2026-10-22 19:34 · **Faz:** M0 (walking skeleton) — derleniyor ve çalışıyor; ölçümler kullanıcı adımı bekliyor

## Kapılar
| Kapı | Durum | Not |
|---|---|---|
| G0 Fikir/karar | ✅ | PRD §1 |
| G1 PRD imzası | ⏳ **imza bekliyor** | Açık madde: Anthropic koşulları (yerel CLI'ı saran kişisel istemci) |
| G2 Mimari + spike | ✅ | ADR-0001…0005, THREAT_MODEL, `make spike` PASS (CLI 2.1.308) |
| M0 Walking skeleton | 🟡 çalışıyor, ölçüm yok | Uygulama açılıyor, geçmiş listeleniyor ve oynatılıyor. İlk token ölçümü ve hitch ölçümü aşağıdaki iki kullanıcı adımına bağlı |
| M1–M3 | 🟡 kodun çoğu M0 ile birlikte yazıldı | Ölçüm/cila M3 |

## Doğrulanan (2026-10-22, bu Mac: macOS 27.0.1, Xcode 27.1)
- `make core-test`: **24/24 test, 8 suite geçti.**
- `make build` (Debug) ve Release derlemesi: **BUILD SUCCEEDED.** İmzada `com.apple.security.app-sandbox = false` korunuyor.
- Uygulama açılıyor; CLI bulunuyor (`CLI found version=2.1.301`), kenar çubuğu `~/.claude/projects` geçmişini projelere göre listeliyor.
- Uzun bir terminal session'ı (araç kartları + diff) açılıp kaydırıldı, çökme yok. Kanıt: [evidence/m0-history-transcript.jpg](evidence/m0-history-transcript.jpg).
- Sohbet modu: yeni session açılıyor, mesaj gidiyor, CLI hatası transcript'te bildirim olarak görünüyor. Kanıt: [evidence/m0-chat-auth-error.jpg](evidence/m0-chat-auth-error.jpg), log: [evidence/m0-monster.log](evidence/m0-monster.log).
- Uygulama kapanınca başlattığı `claude` süreci de sonlanıyor (T-10).
- `glassEffect(` yalnızca `App/Design/Theme.swift` içinde (ADR-0004 kural 1).

## Bu oturumda düzeltilenler
- **Çökme (EXC_BAD_ACCESS, SwiftUI erişilebilirlik etiketinde sonsuz özyineleme):** erişilebilirlik istemcisi (VoiceOver,
  otomasyon) transcript'i okuyunca uygulama düşüyordu. Sebep: seçilebilir `Text`'i saran konteynere `.accessibilityLabel`
  (`UserBubble`) ve `.combine` + etiket (`DiffLine`). İkisi de `.accessibilityElement(children: .ignore)` + etiket oldu.
  Düzeltmeden sonra aynı ekran ve uzun bir session okunarak çökme tekrarlanmadı. Crash raporları:
  `~/Library/Logs/DiagnosticReports/Monster-2026-10-22-192913.ips`, `…-192954.ips`.
- **`xcodegen` entitlements'ı eziyordu:** `project.yml`'deki `entitlements:` anahtarı her `make project`'te
  `Monster.entitlements`'ı boş `<dict/>` ile yazıyordu. Artık yalnızca `CODE_SIGN_ENTITLEMENTS` ile yol veriliyor.
- **`make core-test` codesign hatası:** repo iCloud ile eşitlenen `~/Documents` altında; derleme çıktılarındaki genişletilmiş
  öznitelikler codesign'ı `resource fork, Finder information, or similar detritus not allowed` ile düşürüyordu. Çıktılar
  `~/Library/Caches/Monster-build` altına taşındı (`BUILD_ROOT`).
- PRD'deki proje klasörü yolu ve README'deki CLI/giriş notları düzeltildi.

## M0 ölçümleri (2026-10-22 20:02–20:08, Release, CLI 2.1.308, model claude-fable-5-1, Sohbet modu)
| Ölçüm | Değer | Not |
|---|---|---|
| İlk token, 1. tur (gönder → ekranda ilk asistan metni) | **7240 ms** | Uçtan uca; model düşünmesi + soğuk bağlam dahil |
| İlk token, 2. tur (aynı süreç) | **2047 ms** | Uçtan uca |
| Monster'ın kendi ek gecikmesi (PRD hedefi < 50 ms) | **ölçülmedi** | Uygulama CLI'ın `result.ttft_ms` değerini loglamıyor; ikisi yan yana loglanmalı |

| **Hitch oranı, akış sırasında (PRD hedefi < 5 ms/s)** | **296 ms/s — hedefin ~60 katı ❌** | Instruments "Animation Hitches", Release, 30 sn, 2. tur akarken; pencere 200 Hz harici ekranda |
| Hitch sayısı / en uzun | 1671 / 50 ms | Sebep dağılımı: "expensive render" 1028, "expensive app update + render" 394, "expensive app update" 145 |
| Olası takılma (interaction delay) | 9 adet, ~56 ms | Ana thread |
| Gösterilen kare/sn | 0–174 arası dalgalı | Sabit 200 Hz'e yakın değil |

Hitch notları: Kayıt sırasında 2 erişilebilirlik ekran görüntüsü alındı (otomasyon), bunlar küçük bir pay ekleyebilir. "Expensive render"
baskınlığı GPU tarafını (her satırda `Glass.clear` + yansıma kenarı + kayan aura) işaret ediyor; ADR-0004'te öngörülen risk ölçüldü.
Trace dosyası depoya konmadı (büyük); yeniden üretmek için: Release'i aç, `xcrun xctrace record --template "Animation Hitches" --attach <pid> --time-limit 30s`
(kaydetme ~5 dk sürüyor).

Log: [evidence/m0-monster-run2.log](evidence/m0-monster-run2.log). Akış ekranı: [evidence/m0-streaming-code.jpg](evidence/m0-streaming-code.jpg),
[evidence/m0-chat-done.jpg](evidence/m0-chat-done.jpg).

## Engelli (kullanıcı adımı gerekiyor) — 2026-10-22 20:00'de kullanıcı tarafından çözüldü
1. **İlk token gecikmesi ölçülemedi:** bağımsız `claude` CLI'ı (`~/.local/bin/claude` 2.1.301) giriş yapmamış
   (`claude auth status` → `loggedIn: false`); Monster'dan giden mesaj `Failed to authenticate: OAuth session expired and
   could not be refreshed` ile döndü. Claude masaüstü uygulamasının girişi kendi gömülü CLI'ına (2.1.308) ait, bağımsız CLI'a taşınmıyor.
   → Kullanıcı terminalde `claude` çalıştırıp `/login` yapmalı.
2. **Glass/hitch performansı ölçülemedi:** `xctrace record --attach` takılı kaldı; `DevToolsSecurity -status` →
   "Developer mode is currently disabled". → Kullanıcı `sudo DevToolsSecurity -enable` çalıştırmalı (ya da Instruments'ın
   istediği yetkiyi onaylamalı).

## Composer P1 (2026-10-22): slash komutları, @dosya, görsel/dosya ekleme
- **Spike (gerçek CLI 2.1.308):** komut listesi `initialize` cevabında (`commands`: ad, açıklama, argumentHint, aliases, builtin; 136 komut).
  Slash komutu stdin'e düz metin gider, CLI çalıştırır (`/context` maliyetsiz döndü). Görsel `image` içerik bloğu çalışıyor.
  **`@dosya` CLI tarafından açılmıyor** (model dosyayı Bash ile okumaya gitti) → Monster içeriği `<file path>` metin bloğu olarak ekler.
- **Çekirdek (testli, 46/46):** `SlashCommand` + arama (önek → ad alanı sonrası → içeren → açıklama; `__` iç komutlar gizli; HTML kaçışları çözülür),
  `MentionQuery`/`FileIndex` (bulanık, ağır dizinler atlanır, ≤ 20k dosya), `MentionResolver` (kök dışı reddedilir, ≤ 256 KB metin, aksi halde yol),
  `Attachment` (tür ilk baytlardan, görsel ≤ 5 MB, ≤ 10 ek), `UserMessage` (ek yoksa düz metin, varsa bloklar).
- **Uygulamada doğrulandı (Release, Sonnet, test projesi):** `/` ile 8 öneri, `/con` süzmesi, ↓ + ⇥ ile `/context ` tamamlama ve gönderme (sonuç geldi);
  `@sec` → `src/secret-note.txt` önerisi ve ⇥; ⌘V ile görsel çipi (küçük resimli); gönderim → cevap `mavi-kuzgun-7|yeşil` (dosya içeriği satır içi
  gitti, araç kullanılmadı; görsel rengi doğru). Log: `turn ttft monster=1424ms cli=2270ms` — iki ölçüm farklı tanımlı, fark ek yük değil.
- **Doğrulanmadı:** sürükle-bırak, ataş düğmesiyle dosya seçme (seçici açılıyor, dosya seçilmedi), metin yapıştırmanın bozulmadığı (yakalayıcı metin varken
  olayı geçirir — kod okundu, elle denenmedi), sohbet modunda ek gönderme.
- **Bozuk bulunup düzeltilenler:** `onPasteCommand` TextField'da hiç tetiklenmiyordu → yerel ⌘V olay izleyicisi; `__remote-workflow` iç komutu listede görünüyordu.
- **Güvenlik incelemesi (@security-reviewer, 2026-10-23):** CRITICAL/HIGH yok; 5 LOW + 1 hipotez, hepsi düzeltildi ve testlendi (50/50):
  kontrol–okuma yarışı ve sınırsız okuma (`SafeFile`: `O_NOFOLLOW`, `F_GETPATH`, sınırlı okuma), FIFO'da ana thread kilidi, öneri aramasının
  her gövde yenilemesinde tekrarlanması (önbellek), `</file>` ile sınırlayıcı kırma (rastgele sınırlayıcı), çoklu pencerede ⌘V (pencere denetimi).
  Elle yeniden denendi: `@` önerisi, görsel yapıştırma, metin yapıştırma (bozulmadı, ek eklenmedi). Kalan kabul edilen riskler THREAT_MODEL'de.
- **Geçmiş görünümü:** satır içi dosya bloğu yeniden yüklemede ayrı balon olarak görünüyordu; artık canlıdaki gibi tek balonda `📎 yol` / `🖼 görsel` satırı.
- **Gözlem:** composer'a ilk `/` yazıldığında model menüsü bir kez kendiliğinden açıldı; tekrarlanmadı, sebep bulunmadı.

## Tema revizyonu (2026-10-22, kullanıcı isteği)
Tek renkli açık + koyu tema (ADR-0004 kural 8): aura, mor/indigo vurgu ve `sparkle` kaldırıldı; vurgu = metin rengi; anlamlı renkler
(`danger/warning/success`, diff) kısık ve temaya göre; Ayarlar'da Sistem/Açık/Koyu seçimi. `make build` geçti.
**Görsel olarak doğrulanmadı:** ekran kilitli olduğu için iki temanın ekran görüntüsü alınamadı. Hitch ölçümü aura kalkmadan önce
alındı; aura (sürekli animasyonlu katman) kalktığı için değişmesi beklenir, yeniden ölçülmeli.

## Hitch karşılaştırması (aynı senaryo: Release, koyu tema, Sohbet'te ikinci tur akarken 30 sn, kayıtta 2 otomasyon ekran görüntüsü)
| Sürüm | ms/s | Hitch | En uzun | Baskın sebep |
|---|---|---|---|---|
| İlk tema (renkli, 24 sn kayan aura) | 296 | 1671 | 50 ms | render (GPU) |
| Tek renkli, aura yok | 121 | 477 | 265 ms | app update (CPU) |
| Tek renkli + grisaille tuval (statik) | 82 | 357 | 50 ms | app update + render karışık |

Hedef < 5 ms/s; hâlâ ~16 kat üstünde. Kalan yük akış sırasındaki SwiftUI güncellemeleri. Son ölçümde pencere 1133×608 idi
(öncekilerde 901×573), farklı cevap metinleri; ölçümler arası değişkenlik yüksek, tek koşu. Ekran görüntüleri:
`evidence/theme-*.jpg` (tek renkli), `evidence/oil-*.jpg` (grisaille).

## Metrik doğruluğu düzeltmeleri (2026-10-22, testli)
- `total_cost_usd` süreç içinde kümülatif; her `result`'ta toplanıyordu → iki tur sonunda tutar şişiyordu ($11,13 görüldü). Artık
  süreç başına son değer + biten süreçlerin toplamı. Test: `cumulativeCostIsNotDoubleCounted`, `costAccumulatesAcrossProcesses`.
- Bağlam penceresi bilinmeden 200k varsayılıyordu → 551k token'lık sohbet halkayı kırmızı/%100 gösteriyordu. Artık pencere
  bilinene kadar yüzde yok, token sayısı gösteriliyor. Test: `contextFractionIsUnknownUntilWindowIsReported`.
- Pencere tüm modellerin en büyüğünden seçiliyordu; artık session'ın ana modelininki. Test: `contextWindowFollowsMainModel`.
- Claude uygulamasındaki gibi 5 saatlik ve haftalık plan limitleri ayrı ayrı. Test: `planLimitWindowsAreParsed`.
- Başlıkta $ yerine bağlam %; maliyet ayrıntıda "API karşılığı, liste fiyatı tahmini" olarak. İlk token satırı CLI'ın `ttft_ms`'ini de gösteriyor;
  log'a `turn ttft monster=… cli=…` yazılıyor.
- Monster sohbetlerinde her turda ~551k token istem: CLI tüm global kuralları/MCP/skill'leri yüklüyor. Bkz. [PARITY.md](PARITY.md).

## Gözlemler (ölçülmedi, ekrandan)
- **Okunurluk (ADR-0004 A riski görüldü):** composer'ın `clear` glass'ı altından kayan araç kartlarının metni, "Give Claude Code a task…"
  yer tutucusuyla üst üste okunuyor (evidence/m0-history-transcript.jpg).
- **Geçmiş session'ı yalnızca seçmek `claude --resume <id>` süreci başlatıyor** (prewarm). Seçilen session başka bir istemcide
  (terminal, Claude masaüstü) canlıysa aynı session'a ikinci bir süreç bağlanıyor. Mesaj gönderilmeden JSONL'a yazıp yazmadığı
  doğrulanmadı. Öneri: terminal/harici session'lar için prewarm'ı ilk mesaja ertelemek.
- UI İngilizce açıldı (kaynak dil TR). Muhtemelen sistem dili İngilizce olduğu için; sistem dili kontrol edilmedi.

## Sıradaki adımlar
1. Kullanıcı: `claude` → `/login`; `sudo DevToolsSecurity -enable`.
2. M0 kanıtı: Sohbet modunda mesaj → Console'da `first token latency=…ms`; aynı sırada Instruments "Animation Hitches" (Release).
3. Prewarm/resume yan etkisi için karar (yukarıdaki gözlem).
4. G1: koşulların kontrolü ve PRD imzası.
5. M3: Instruments (SwiftUI + Hitches), a11y ekran görüntüleri, `make release` ile imzalı .app.
