# ADR-0005 — Dağıtım: Developer ID + Hardened Runtime, App Sandbox yok

**Durum:** Kabul · **Tarih:** 2026-10-22

## Bağlam
Nova kullanıcının `claude` çalıştırılabilirini (çoğu zaman `~/.local/bin` altında, kendisi de node/bun çalıştıran)
alt süreç olarak başlatır ve CLI kullanıcının proje klasörlerinde serbestçe okuyup yazar. App Sandbox'ta alt süreçler
sandbox'ı miras alır; CLI ev dizinine, `~/.claude`'a ve projelere erişemez.

## Karar
- `com.apple.security.app-sandbox = false`, `ENABLE_HARDENED_RUNTIME = YES`.
- İmza: Developer ID Application + `--timestamp`; `notarytool` ile notarize (`make release`).
- **Mac App Store hedeflenmez.**

## Sonuçlar ve telafi edici kontroller
- Shell yok, argüman listesi (T-1); widget'lar ayrı ve kısıtlı WebView'da (T-3); Full access kapılı (T-4);
  loglarda içerik yok (T-6). Ayrıntı: [THREAT_MODEL.md](../THREAT_MODEL.md).
- Hardened Runtime ile ek istisna (JIT, unsigned memory, DYLD env) **istenmez**.
