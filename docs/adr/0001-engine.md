# ADR-0001 — Motor: `claude` CLI'ı doğrudan alt süreç olarak çalıştırmak

**Durum:** Kabul · **Tarih:** 2026-10-22 · **Kanıt:** [G2 spike](../spike/G2-stream-json.md)

## Bağlam
Nova API anahtarı tutmaz; kullanıcının kurulu Claude Code CLI'ını ve girişini kullanır. İki yol vardı:
1. Swift `Process` ile `claude -p --input-format stream-json --output-format stream-json …`
2. Node sidecar + Claude Agent SDK, Nova ile yerel IPC

## Karar
**(1) Doğrudan CLI.** Her session = bir alt süreç (`ClaudeProcess`), hepsi `AgentEngine` actor'ı altında.

- Argümanlar `Process.arguments` listesiyle verilir; **shell yok**. Kullanıcı metni yalnızca stdin'e JSON olarak gider.
- İzinler: `--permission-prompts host --permission-prompt-tool stdio` → `control_request/can_use_tool`.
- stdout `readabilityHandler` → `NDJSONLineSplitter` → `InboundMessage` (toleranslı `JSONValue` ağacı).
- Bilinmeyen `type`/`subtype` hata değildir (`.unknown`), akış durmaz.
- CLI sürümü `--version` ile okunur; `CLILocator.testedVersion` (2.1.x) dışında UI uyarı gösterir.

## Sonuçlar
- ➕ Ek runtime yok, tek IPC katmanı, terminal session'larıyla birebir aynı davranış ve `--resume`.
- ➕ Gecikme: CLI'dan sonra Nova'nın eklediği tek şey satır ayrıştırma + kare toplama (≤16 ms).
- ➖ stream-json formatı CLI sürümleriyle değişebilir → toleranslı parser, fixture testleri, `make spike`.
- ➖ App Sandbox ile alt süreç çalıştırma çakışır → ADR-0005.

## Alternatif (reddedildi, gerekirse v1.1)
Agent SDK sidecar: SDK'nın tipli API'si cazip ama aynı CLI'ı sarıyor; node bağımlılığı ve ikinci süreç ağacı getiriyor.
