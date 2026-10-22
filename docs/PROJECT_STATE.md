# PROJECT_STATE

**Son güncelleme:** 2026-10-22 · **Faz:** G2 tamam → M0 (walking skeleton) kodu yazıldı, Mac'te derleme bekliyor

## Kapılar
| Kapı | Durum | Not |
|---|---|---|
| G0 Fikir/karar | ✅ | PRD §1 |
| G1 PRD imzası | ⏳ **imza bekliyor** | Açık madde: Anthropic koşulları (yerel CLI'ı saran kişisel istemci) |
| G2 Mimari + spike | ✅ | ADR-0001…0005, THREAT_MODEL, `make spike` PASS (CLI 2.1.308) |
| M0 Walking skeleton | 🟡 kod hazır | Mac'te `make project && make run` + ekran kaydı + ilk token ölçümü gerekiyor |
| M1–M3 | 🟡 kodun çoğu M0 ile birlikte yazıldı | Ölçüm/cila M3 |

## Doğrulanan
- `make spike`: stream-json, `text_delta`, `can_use_tool` → allow + `updatedPermissions`, dosya yazıldı, ikinci tur, interrupt → `error_during_execution`.
- Fixture'lar gerçek CLI çıktısı.

## Doğrulanmayan (dürüst durum)
- **Swift kodu henüz derlenmedi.** Bu repo bir Linux konteynerde yazıldı; Swift araç zinciri ve macOS SDK orada yoktu.
  İlk iş: Mac'te `make core-test` ve `make build`; çıkan derleme hataları düzeltilir.
- macOS 26/27'ye özgü API'ler (`Glass.clear`, `glassEffectTransition(.matchedGeometry)`, `ToolbarSpacer`,
  `scrollEdgeEffectStyle`, SF Symbols 7 `drawOn`) Xcode 27.1'de doğrulanacak.
- Performans metrikleri (hitch, 120 fps, soğuk açılış) ölçülmedi.
- Reduce Transparency / Increase Contrast / Reduce Motion ekran görüntüsü kanıtları alınmadı.

## Sıradaki adımlar
1. Mac'te: `make bootstrap project core-test build run`.
2. M0 kanıtı: ekran kaydı + Console'da `first token latency=…ms` (subsystem `app.nova`).
3. G1: koşulların kontrolü ve PRD imzası.
4. M3: Instruments (SwiftUI + Hitches), a11y ekran görüntüleri, `make release` ile imzalı .app.
