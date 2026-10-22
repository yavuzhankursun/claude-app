# Nova — PRD (MVP, macOS)

Kendi Claude Code istemcimiz. **Tarih:** 2026-10-22 · **Süre:** 4 hafta · **Metot:** app-forge (G0→G6)

## 1. Kararlar (kullanıcı onaylı)
| Konu | Karar |
|---|---|
| Platform | Yalnızca macOS (iPhone yok) |
| SDK | En güncel Apple SDK: **macOS 27 SDK / Xcode 27.1**, Swift 6 dil modu; dağıtım hedefi **macOS 26** (Liquid Glass) |
| Ajan | Yalnızca Claude Code; Sohbet + Kod modu |
| Makine | Tek Mac; çoklu makine v1.1 |
| Tasarım | **Her parçada en şeffaf Liquid Glass (`Glass.clear`) + yansıma kenarı; animasyonlar tüm modüllerde tek kurala uyar** (ADR-0004, 2026-10-22 revizyonu) |
| Süre | 4 hafta |

## 2. Varsayımlar
- UI dili TR (kaynak) + EN (`Localizable.xcstrings`). Commit: her seferinde sorulur.
- Uygulama API anahtarı tutmaz; kurulu `claude` CLI'ı ve onun girişini kullanır.
  **Açık risk (G1):** Anthropic koşullarının kişisel kullanım için yerel CLI'ı saran bir istemciye izin verdiği doğrulanacak; gerekirse "API key modu".
- Proje klasörü kullanıcının Mac'inde: `~/Desktop/nova` (bu repo).

## 3. Mimari
```
┌──────────── Nova.app (SwiftUI, macOS 26+, macOS 27 SDK) ─────────────┐
│ UI: NavigationSplitView · her yüzey novaGlass(.clear + specular rim) │
│   Sidebar · Transcript · Composer · İzin kartı · ⌘K palet            │
│ Render: MarkdownParser · SyntaxHighlighter · LineDiff · WKWebView     │
│ Store: SwiftData (SessionRecord meta) · ~/.claude/projects (salt-oku) │
│ AgentEngine (actor) ── her session = 1 ClaudeProcess                  │
└───────────────┬──────────────────────────────────────────────────────┘
                │ stdin/stdout NDJSON (control_request/response)
  claude -p --input-format stream-json --output-format stream-json --verbose
         --include-partial-messages --permission-prompts host
         --permission-prompt-tool stdio [--resume|--session-id] --permission-mode …
```
Motor kararı G2 spike'ında verildi: **doğrudan CLI** (ADR-0001, [spike raporu](spike/G2-stream-json.md)).

- **Sohbet modu:** `~/Library/Application Support/Nova/Chats/<id>` boş dizini; araçlar `Read,Glob,Grep,WebSearch,WebFetch`;
  `Bash/Edit/Write/NotebookEdit` yasak; izin modu her zaman `default`.
- **Kod modu:** seçilen klasör; Ask / Auto-edit / Plan / Full access.
- **Geçmiş:** `~/.claude/projects/*/*.jsonl` salt-okunur indekslenir; terminal session'ları listede, `--resume` ile devam.
- **İzin:** `can_use_tool` → glass izin kartı (İzin ver / Bu session için / Reddet).
- **Widget:** kapanmış ```` ```svg ```` / ```` ```html ```` blokları CSP'li, JS'siz, ağsız WKWebView'da.

## 4. MVP kapsamı
| Hikâye | Durum (bkz. PROJECT_STATE) |
|---|---|
| US-1 Session listesi: projeye göre gruplu, arama, canlı gösterge | kodlandı |
| US-2 Yeni session: Sohbet/Kod, klasör, model, effort | kodlandı |
| US-3 Canlı transcript: streaming, katlanır düşünme, araç kartları | kodlandı + test |
| US-4 İzin akışı + izin modu değiştirme | kodlandı + test + spike |
| US-5 Devam/geçmiş (terminal dahil `--resume`) | kodlandı + test |
| US-6 Zengin render: Markdown, highlight, diff, SVG/HTML widget | kodlandı + test |
| US-7 Esc ile durdurma, token/maliyet, bağlam doluluğu | kodlandı + test |

Kapsam dışı (v1.1+): çoklu makine, iPhone, Codex, tarayıcı paneli, artifact yayınlama, MCP UI. Non-goal: kendi model sağlayıcısı, bulut senkronu.

## 5. Milestone'lar
| Hafta | Milestone | Kanıt |
|---|---|---|
| 0.5 | G0–G2: PRD, ADR'ler, tehdit modeli, spike | ✅ `make spike` PASS, docs/ |
| 1 | M0 walking skeleton | Xcode build + ekran kaydı + ilk token ölçümü (Mac'te) |
| 2 | M1 Session yönetimi (US-1/2/5) | |
| 3 | M2 Transcript + izin (US-3/4/6) | |
| 4 | M3 Cila: morph'lar, kısayollar, Instruments, a11y, güvenlik, imzalı .app | |

## 6. Başarı metrikleri
| Metrik | Hedef |
|---|---|
| CLI'dan sonra ilk token'ın ekrana gelmesi (ek gecikme) | < 50 ms |
| Streaming hitch oranı | < 5 ms/s |
| 1.000 mesajlık transcript kaydırma | 120 fps |
| Soğuk açılış | < 1 s |
| Crash-free oturum | > %99.5 |

## 7. Riskler
- stream-json formatı değişir → toleranslı parser, fixture'lar, `make spike`, sürüm uyarısı.
- Abonelik + 3. taraf istemci koşulları → G1 (açık).
- **Her yerde clear glass + uzun liste performansı** → ADR-0004'teki önlemler, M0'dan itibaren ölçüm.
- Kapsam şişmesi → [BACKLOG.md](BACKLOG.md).
