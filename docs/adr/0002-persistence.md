# ADR-0002 — Kalıcılık: SwiftData'da yalnızca meta veri; transcript CLI'da kalır

**Durum:** Kabul · **Tarih:** 2026-10-22

## Karar
- **Doğruluk kaynağı** CLI'ın `~/.claude/projects/<kodlanmış-yol>/<session-id>.jsonl` dosyalarıdır. Monster bunları
  **salt-okunur** indeksler (`HistoryIndexer`) ve tekrar oynatır (`HistoryLoader`). Monster bu dosyalara asla yazmaz/silmez.
- **SwiftData** (`SessionRecord`): başlık, mod, proje/çalışma dizini, model, effort, izin modu, CLI session id'si,
  zaman damgaları. Transcript kopyalanmaz → çift kaynak ve senkron sorunu yok.
- Yeni session'larda CLI id'sini biz üretiriz (`--session-id <uuid>`); dosya oluştuktan sonra `--resume <id>`.
- Terminal session'ları kenar çubuğunda ayrı listelenir; seçilince `SessionRecord`'a aktarılır ve `--resume` ile devam eder.
- İndeksleme büyük dosyalarda baştan 128 KB + sondan 64 KB okur; `(mtime, size)` önbelleği ile tekrar okumaz.

## Sonuçlar
- ➕ Uygulama kapanıp açılınca kaldığı yerden (US-5), terminal ve Monster aynı geçmişi görür.
- ➖ JSONL formatı da sürümle değişebilir → toleranslı okuma; başlık için `custom-title` / `ai-title` / `summary` satırları denenir.
- Şema bozulursa uygulama bellek-içi depoyla açılır (CLI geçmişi etkilenmez).
