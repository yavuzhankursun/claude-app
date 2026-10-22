# G2 Spike — `claude` stream-json + izin protokolü

**Tarih:** 2026-10-22 · **CLI:** 2.1.308 · **Sonuç:** ✅ PASS (`make spike`)

Amaç (PRD §9 "İzin isteği protokolü beklenenden farklı" riski): Monster'ın CLI'ı doğrudan alt süreç olarak sürebileceğini kanıtlamak.

## Başlatma

```
claude -p --input-format stream-json --output-format stream-json --verbose \
  --include-partial-messages \
  --permission-prompts host --permission-prompt-tool stdio \
  [--model …] [--effort …] [--permission-mode default|acceptEdits|plan|bypassPermissions] \
  [--resume <id> | --session-id <uuid>]
```

**Kritik bulgu:** `--permission-prompts host` tek başına yetmiyor. `--permission-prompt-tool stdio` verilmezse
izin gerektiren araçlar sessizce reddediliyor (`"Claude requested permissions … but you haven't granted it yet"`).
İkisi birlikte verilince CLI stdout'a `control_request` yazıyor.

## Mesajlar (stdout, satır başına bir JSON)

| type / subtype | Kullanım |
|---|---|
| `system/init` | session_id, model, cwd, permissionMode, claude_code_version |
| `system/status` | `requesting`; izin modu değişince `permissionMode` |
| `system/post_turn_summary` | tur sonu tek satır özet |
| `stream_event` | ham Messages API event'leri: `message_start`, `content_block_start/delta/stop` (`text_delta`, `thinking_delta`, `input_json_delta`, `signature_delta`), `message_delta`, `message_stop`. `api_message_id` taşır |
| `assistant` | **blok başına bir satır**, aynı `message.id` ile; akıştan *önce değil sonra* gelir |
| `user` | `tool_result` blokları; interrupt sonrası `"[Request interrupted by user]"` metni |
| `result` | `subtype` (`success` / `error_during_execution`), `is_error`, `total_cost_usd`, `usage`, `modelUsage.<m>.contextWindow`, `ttft_ms` |
| `control_request/can_use_tool` | `tool_name`, `display_name`, `input`, `description`, `tool_use_id`, `permission_suggestions` |
| `control_response` | Monster'ın isteklerine cevap (`initialize`, `interrupt`, `set_permission_mode`, `set_model`) |
| `rate_limit_event`, `active_goal`, `autocompact_state`, … | bilinmeyenler yok sayılır |

## Monster → CLI (stdin)

```jsonc
{"type":"user","message":{"role":"user","content":"…"}}
{"type":"control_request","request_id":"…","request":{"subtype":"initialize"}}
{"type":"control_request","request_id":"…","request":{"subtype":"interrupt"}}
{"type":"control_request","request_id":"…","request":{"subtype":"set_permission_mode","mode":"acceptEdits"}}
{"type":"control_request","request_id":"…","request":{"subtype":"set_model","model":"opus"}}
// izin cevabı
{"type":"control_response","response":{"subtype":"success","request_id":"<CLI'ın id'si>",
  "response":{"behavior":"allow","updatedInput":{…},"updatedPermissions":[…öneriler…]}}}
{"type":"control_response","response":{"subtype":"success","request_id":"…",
  "response":{"behavior":"deny","message":"…"}}}
```

- `updatedPermissions` = CLI'ın `permission_suggestions`'ı → "Bu session için". Örnek öneri
  `{"type":"setMode","mode":"acceptEdits","destination":"session"}` uygulanınca `system/status` ile mod `acceptEdits` oluyor.
- `set_permission_mode: bypassPermissions` süreç `--allow-dangerously-skip-permissions` ile başlatılmadıysa
  `error_code: bypass_not_launched` döner. Monster kod modunda bu seçeneği açar, geçişi UI'da onayla kapılar.
- Bilinmeyen control subtype → `"Unsupported control request subtype"` hatası; süreç çökmez.
- Süreç stdin kapanana kadar yaşar; aynı süreçte çok tur çalışır.

## Ölçümler (bu konteyner, haiku)

| | |
|---|---|
| spawn → ilk stdout baytı | ~750 ms (Monster bunu *prewarm* ile kullanıcıdan gizler) |
| interrupt → `result` | ~25 ms |
| İzin turu (gönder → `can_use_tool`) | model süresine bağlı |

Monster'ın kendi ek gecikmesi (stdout satırı → ekranda) hedefi < 50 ms; kare bütçesi 16 ms (SessionController).

## Fixture'lar

`MonsterCore/Tests/MonsterCoreTests/Fixtures/*.ndjson` — bu spike'ın gerçek çıktıları; yollar, session id'leri ve
init'teki makineye özgü listeler anonimleştirildi. Reducer ve parser testleri bunlarla çalışır.

## Karar girdisi (ADR-0001)

Doğrudan CLI yolu tüm MVP gereksinimlerini karşılıyor; Node sidecar + Agent SDK'nın ek bir runtime (node),
ek bir IPC katmanı ve ayrı sürüm takibi maliyeti var. → **Doğrudan CLI.**
