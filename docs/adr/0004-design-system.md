# ADR-0004 — Tasarım sistemi: her yerde şeffaf Liquid Glass + tek hareket dili

**Durum:** Kabul (revize: 2026-10-22, kullanıcı kararı) · **SDK:** macOS 27 SDK (Xcode 27.1), hedef macOS 26+

## Revizyon
İlk plan glass'ı yalnızca yüzen katmanla sınırlıyordu. Kullanıcı kararı: **her parçada Liquid Glass'ın en şeffaf ve
yansımalı efekti olacak; animasyonlar tüm modüllerde bu kurala birebir uyacak.** Bu ADR o kuralı kodlar.

## Kural
1. **Tek giriş noktası.** Görünümler `.glassEffect(...)` / `.buttonStyle(.glass…)` çağırmaz; yalnızca
   `monsterGlass(...)` ve `MonsterGlassButtonStyle` (`App/Design/Theme.swift`). `grep -rn "glassEffect(" App` yalnızca
   `Theme.swift`'i göstermelidir.
2. **Varyant:** `Glass.clear` (en şeffaf) + `.interactive()` (pointer'a göre ayarlı tepki) + isteğe bağlı ton.
3. **Yansıma:** her glass yüzeyde `SpecularRim` — üst-sol ışıktan gelen degrade kenar (`plusLighter`), Increase
   Contrast'ta kalınlaşır.
4. **Kapsam:** composer, gönder/durdur, izin kartı, durum pili, komut paleti, rozetler, **mesaj balonları, asistan
   tabloları, kod blokları, diff, araç kartları, düşünme bloğu, bildirimler**, tüm butonlar. Kenar çubuğu, toolbar,
   popover ve menüler macOS'un kendi Liquid Glass'ı ile çizilir (sistem varyantı değiştirilemez).
5. **Zemin:** grisaille yağlı boya tuvali (kural 9). Aura yok.
6. **Hareket:** yalnızca `Motion.glass` (`.smooth(0.42, bounce 0.08)`) ve `Motion.snap` (`.snappy(0.26)`).
   Glass öğeleri `glassEffectTransition(.matchedGeometry)` taşır; yüzen katman tek `GlassEffectContainer` içinde
   `glassEffectID` ile morph eder (composer ↔ izin kartı ↔ durum pili). Yeni transcript satırları `.blurReplace` ile belirir.
   Basma geri bildirimi tüm butonlarda aynı (0.96 ölçek, `Motion.snap`).
7. **Erişilebilirlik:** Reduce Motion → tüm `Motion` değerleri `nil`. Reduce Transparency → sistem glass'ı
   opaklaştırır. Increase Contrast → yansıma kenarı belirginleşir.
8. **Renk ve tema (revizyon 2026-10-22, kullanıcı kararı: "AI tarzı renkler olmasın, açık ve koyu tema, Grok gibi"):**
   - Dekoratif renk yok: mor/indigo vurgu, renkli aura, `sparkle` simgesi kaldırıldı.
   - Vurgu = metin rengi: `Theme.accent` koyuda beyaz, açıkta siyah; birincil buton üzerindeki metin `Theme.onAccent`.
     Assets'teki `AccentColor` ise nötr koyu gri: macOS kenar çubuğu seçimini onunla çizip üstüne beyaz metin koyuyor.
   - Renk yalnızca anlam taşırken ve kısık tonda: `danger`, `warning`, `success`, diff +/-. Kod vurgusu neredeyse tek renkli.
   - Açık + koyu tema; Ayarlar › Genel › Görünüm: Sistem / Açık / Koyu (`AppearancePreference`, varsayılan Sistem).
   - Yansıma kenarı (`SpecularRim`) temaya göre: koyuda beyaz + `plusLighter`, açıkta beyaz üst / koyu alt kenar + normal karışım.
9. **Cam + yağlı boya (revizyon 2026-10-22, kullanıcı: "camsı ve yağlı boya bir arada", sanat yönü Claude'a bırakıldı):**
   - Yön: **grisaille** — klasik yağlı boyanın yalnızca gri tonlarla yapılan alt boyaması. Renksiz kaldığı için kural 8'i bozmaz.
   - Katmanlar: geniş alt boyama süpürmeleri → akış alanını izleyen fırça darbeleri (kıl izleriyle) → ışığı yakalayan impasto
     sırtları → keten tuval dokusu. Merkez sakin, hareket kenarlarda (okunurluk).
   - Neden: `Glass.clear` düz zeminde kıracak bir şey bulamıyordu; dokulu tuval camı görünür kılar.
   - Performans: `PaintedCanvas` tema başına bir kez, deterministik çizilip `NSImage` olarak önbelleğe alınır; ekranda statik
     görüntüdür, animasyon yok. Reduce Transparency ve Increase Contrast'ta tuval gizlenir, düz zemin kalır.

## Bilinen bedeller ve önlemler
| Bedel | Önlem |
|---|---|
| `clear` glass üzerinde metin okunurluğu | Zemin koyu ve sakin; metin `primary`/`secondary` hiyerarşisi; Increase Contrast yolu test edilir |
| Uzun transcript'te çok sayıda glass yüzey (GPU) | `LazyVStack` (yalnızca görünür satırlar), `Equatable` satırlar, ≤60 Hz yayın, sürekli animasyonlu zemin yok; M3'te Instruments: hitch < 5 ms/s, 1.000 mesajda 120 fps. Hedef tutmazsa öneri: transcript satırlarını tek `GlassEffectContainer` altında birleştirmek |
| Glass içinde glass (araç kartı içindeki diff/kod) | Kabul edildi (kural gereği); görsel olarak M3'te gözden geçirilecek |

## Değerlendirilen alternatifler (2026-10-22, reddedildi — kullanıcı kararı: A)
- **B. Karma:** gerçek glass yalnızca yüzen katmanda; içerik kartları koyu yarı saydam yüzey + `SpecularRim`, `interactive` yok.
- **C. Apple standardı:** glass yalnızca kontrollerde, içerik düz.

A'nın riskleri bilerek kabul edildi: içerik arkasında kırılacak bir şey olmadığından efektin zayıf görünmesi, aura
üzerinde `clear` metin kontrastı, akış sırasında her karede yeniden örnekleme, iç içe glass, içerikte `.interactive()`.
Tüm glass `monsterGlass(...)` üzerinden geçtiği için M3 ölçümü hedefi tutmazsa B'ye geçiş tek dosyalık bir değişikliktir.

## Akıcılık
- 120 Hz hedefi; token akışı her token'da değil kare başına bir kez yayınlanır (`SessionController.frameBudget = 16 ms`).
- SF Symbols 7: `drawOn` geçişi (araç tamamlandı), `variableColor` (durum pili), `breathe` (karşılama), `replace` içerik geçişleri.
- Mac idiyomları: ⌘K palet, ⌘N / ⇧⌘N, ⌘1…9, Esc durdur, ⌘↩ izin ver, ⌥⌘↩ bu session için, ⌘⌫ reddet, çoklu pencere, Settings.
