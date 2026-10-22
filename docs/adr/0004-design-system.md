# ADR-0004 — Tasarım sistemi: her yerde şeffaf Liquid Glass + tek hareket dili

**Durum:** Kabul (revize: 2026-10-22, kullanıcı kararı) · **SDK:** macOS 27 SDK (Xcode 27.1), hedef macOS 26+

## Revizyon
İlk plan glass'ı yalnızca yüzen katmanla sınırlıyordu. Kullanıcı kararı: **her parçada Liquid Glass'ın en şeffaf ve
yansımalı efekti olacak; animasyonlar tüm modüllerde bu kurala birebir uyacak.** Bu ADR o kuralı kodlar.

## Kural
1. **Tek giriş noktası.** Görünümler `.glassEffect(...)` / `.buttonStyle(.glass…)` çağırmaz; yalnızca
   `novaGlass(...)` ve `NovaGlassButtonStyle` (`App/Design/Theme.swift`). `grep -rn "glassEffect(" App` yalnızca
   `Theme.swift`'i göstermelidir.
2. **Varyant:** `Glass.clear` (en şeffaf) + `.interactive()` (pointer'a göre ayarlı tepki) + isteğe bağlı ton.
3. **Yansıma:** her glass yüzeyde `SpecularRim` — üst-sol ışıktan gelen degrade kenar (`plusLighter`), Increase
   Contrast'ta kalınlaşır.
4. **Kapsam:** composer, gönder/durdur, izin kartı, durum pili, komut paleti, rozetler, **mesaj balonları, asistan
   tabloları, kod blokları, diff, araç kartları, düşünme bloğu, bildirimler**, tüm butonlar. Kenar çubuğu, toolbar,
   popover ve menüler macOS'un kendi Liquid Glass'ı ile çizilir (sistem varyantı değiştirilemez).
5. **Zemin:** glass'ın yansıtacağı içerik — derin siyah gradient (#000 → #0B0B10) + 24 sn'de kayan üç katmanlı aura.
6. **Hareket:** yalnızca `Motion.glass` (`.smooth(0.42, bounce 0.08)`) ve `Motion.snap` (`.snappy(0.26)`).
   Glass öğeleri `glassEffectTransition(.matchedGeometry)` taşır; yüzen katman tek `GlassEffectContainer` içinde
   `glassEffectID` ile morph eder (composer ↔ izin kartı ↔ durum pili). Yeni transcript satırları `.blurReplace` ile belirir.
   Basma geri bildirimi tüm butonlarda aynı (0.96 ölçek, `Motion.snap`).
7. **Erişilebilirlik:** Reduce Motion → tüm `Motion` değerleri `nil`, aura durur. Reduce Transparency → sistem glass'ı
   opaklaştırır, aura kapanır. Increase Contrast → aura kapanır, yansıma kenarı belirginleşir.

## Bilinen bedeller ve önlemler
| Bedel | Önlem |
|---|---|
| `clear` glass üzerinde metin okunurluğu | Zemin koyu ve sakin; metin `primary`/`secondary` hiyerarşisi; Increase Contrast yolu test edilir |
| Uzun transcript'te çok sayıda glass yüzey (GPU) | `LazyVStack` (yalnızca görünür satırlar), `Equatable` satırlar, ≤60 Hz yayın, aura `drawingGroup()`; M3'te Instruments: hitch < 5 ms/s, 1.000 mesajda 120 fps. Hedef tutmazsa öneri: transcript satırlarını tek `GlassEffectContainer` altında birleştirmek |
| Glass içinde glass (araç kartı içindeki diff/kod) | Kabul edildi (kural gereği); görsel olarak M3'te gözden geçirilecek |

## Akıcılık
- 120 Hz hedefi; token akışı her token'da değil kare başına bir kez yayınlanır (`SessionController.frameBudget = 16 ms`).
- SF Symbols 7: `drawOn` geçişi (araç tamamlandı), `variableColor` (durum pili), `breathe` (karşılama), `replace` içerik geçişleri.
- Mac idiyomları: ⌘K palet, ⌘N / ⇧⌘N, ⌘1…9, Esc durdur, ⌘↩ izin ver, ⌥⌘↩ bu session için, ⌘⌫ reddet, çoklu pencere, Settings.
