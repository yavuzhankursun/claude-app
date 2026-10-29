# Monster

**English** | [Türkçe](README.tr.md)

A personal, native macOS client for Claude Code. SwiftUI + Liquid Glass, built against the latest Apple SDK
(**Xcode 27.1 / macOS 27 SDK**, Swift 6), deployment target **macOS 26+**.

Monster holds no API key of its own: it runs the installed `claude` CLI as a subprocess (stream-json) and uses its login.

## Quick start (Mac)

```sh
make bootstrap      # xcodegen (Homebrew)
make core-test      # MonsterCore unit tests
make run            # generate Monster.xcodeproj, build, open
make spike          # protocol validation against the real CLI (haiku, temp directory)
```

Requirements: macOS 26+, Xcode 27.1, Claude Code CLI (tested with 2.1.308) and at least one prior `claude` login.

## Layout

```
App/                 SwiftUI application (Monster.app)
  Design/Theme.swift   glass rules (monsterGlass, MonsterGlassButtonStyle, Motion, surfaces)
  Model/               AppModel, SessionController (per-frame publishing), SessionRecord (SwiftData)
  Views/               Sidebar, Session, Transcript, Composer, Permission, Palette, Settings
MonsterCore/         UI-independent Swift package (swift test)
  Protocol/            JSONValue, InboundMessage, OutboundMessage, NDJSONLineSplitter
  Engine/              AgentEngine (actor), ClaudeProcess, LaunchConfiguration, CLILocator
  Transcript/          TranscriptState reducer (stream + history + permissions + usage)
  History/             ~/.claude/projects indexer (read-only)
  Rendering/ Diff/     Markdown blocks, highlighting, widget CSP, line diff
docs/                PRD, PROJECT_STATE, ADRs, threat model, spike report
scripts/             G2 spike driver
```

## Shortcuts
⌘N new code session · ⇧⌘N new chat · ⌘K command palette · ⌘1…9 switch session · Esc stop ·
↩ send / ⇧↩ new line · On a permission card: ⌘↩ allow, ⌥⌘↩ allow for this session, ⌘⌫ deny.

Status and open items: [docs/PROJECT_STATE.md](docs/PROJECT_STATE.md).
