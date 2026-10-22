# Monster

Claude Code için kişisel, native bir macOS istemcisi. SwiftUI + Liquid Glass, en güncel Apple SDK
(**Xcode 27.1 / macOS 27 SDK**, Swift 6), dağıtım hedefi **macOS 26+**.

Monster kendi API anahtarını tutmaz: kurulu `claude` CLI'ını alt süreç olarak çalıştırır (stream-json) ve onun girişini kullanır.

## Hızlı başlangıç (Mac)

```sh
make bootstrap      # xcodegen (Homebrew)
make core-test      # MonsterCore birim testleri
make run            # Monster.xcodeproj üret, derle, aç
make spike          # gerçek CLI ile protokol doğrulaması (haiku, geçici dizin)
```

Gereksinimler: macOS 26+, Xcode 27.1, Claude Code CLI 2.1.x (spike: 2.1.308; Mac'te çalıştırılan: 2.1.301) ve
bağımsız `claude` CLI'ında geçerli bir giriş (`claude auth status` → `loggedIn: true`). Claude masaüstü uygulamasının
girişi bu CLI'a taşınmaz.

Derleme çıktıları `~/Library/Caches/Monster-build` altına yazılır (`BUILD_ROOT` ile değiştirilebilir). Repo iCloud ile
eşitlenen bir klasördeyse (ör. `~/Documents`) çıktılar orada olursa codesign genişletilmiş öznitelikler yüzünden düşer.

## Yapı

```
App/                 SwiftUI uygulaması (Monster.app)
  Design/Theme.swift   glass kuralı (monsterGlass, MonsterGlassButtonStyle, Motion, zemin)
  Model/               AppModel, SessionController (kare başına yayın), SessionRecord (SwiftData)
  Views/               Sidebar, Session, Transcript, Composer, Permission, Palet, Settings
MonsterCore/         UI'dan bağımsız Swift paketi (swift test)
  Protocol/            JSONValue, InboundMessage, OutboundMessage, NDJSONLineSplitter
  Engine/              AgentEngine (actor), ClaudeProcess, LaunchConfiguration, CLILocator
  Transcript/          TranscriptState reducer (akış + geçmiş + izin + kullanım)
  History/             ~/.claude/projects indeksleyici (salt-okunur)
  Rendering/ Diff/     Markdown blokları, vurgulama, widget CSP, satır diff'i
docs/                PRD, PROJECT_STATE, ADR'ler, tehdit modeli, spike raporu
scripts/             G2 spike sürücüsü
```

## Kısayollar
⌘N yeni kod session'ı · ⇧⌘N yeni sohbet · ⌘K komut paleti · ⌘1…9 session · Esc durdur ·
↩ gönder / ⇧↩ yeni satır · İzin kartında ⌘↩ izin ver, ⌥⌘↩ bu session için, ⌘⌫ reddet.

Durum ve açık maddeler: [docs/PROJECT_STATE.md](docs/PROJECT_STATE.md).
