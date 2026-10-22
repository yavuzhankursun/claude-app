import Foundation
import Testing
@testable import MonsterCore

@Suite("Transcript reducer")
struct TranscriptTests {
    @Test func simpleTurnProducesOneTextItem() throws {
        var state = TranscriptState()
        state.appendLocalUserMessage("Say hi in 3 words.")
        for m in try Fixture.lines("simple-turn") { state.apply(m) }

        #expect(state.items.count == 2)
        #expect(state.items[0].kind == .user("Say hi in 3 words."))
        #expect(state.items[1].kind == .assistantText("Hello there friend!"))
        #expect(state.items[1].isStreaming == false)
        #expect(state.isTurnActive == false)
        #expect(state.contextWindow == 1_000_000)
        #expect(state.totalCostUSD > 0)
        #expect(state.lastTurnSummary?.isEmpty == false)
    }

    @Test func permissionFlowAndInterrupt() throws {
        let messages = try Fixture.lines("permission-then-interrupt")
        var state = TranscriptState()
        state.appendLocalUserMessage("Create b.txt")

        var request: PermissionRequest?
        for m in messages {
            state.apply(m)
            if case .permissionRequest(let r) = m {
                request = r
                #expect(state.pendingPermissions.count == 1)
                guard case .toolCall(let call)? = state.item(id: r.toolUseId!)?.kind else {
                    Issue.record("araç kartı yok"); return
                }
                #expect(call.status == .awaitingPermission)
                state.recordPermissionDecision(r, decision: .allowForSession)
            }
            if case .result(let info) = m, info.subtype == "success" {
                state.appendLocalUserMessage("Write a 300 word essay about cats.")
                state.markInterruptRequested()
            }
        }

        let r = try #require(request)
        guard case .toolCall(let call)? = state.item(id: r.toolUseId!)?.kind else { Issue.record("kart kayboldu"); return }
        #expect(call.status == .succeeded)
        #expect(call.input?["content"]?.stringValue == "y")
        #expect(call.result?.text.contains("File created successfully") == true)
        #expect(state.pendingPermissions.isEmpty)
        #expect(state.permissionMode == .autoEdit)

        // Akış + blok başına `assistant` satırı aynı içeriği iki kez üretmemeli.
        let texts = state.items.compactMap { item -> String? in
            if case .assistantText(let t) = item.kind { return t }
            return nil
        }
        #expect(texts.filter { $0 == "OK" }.count == 1)

        // Durdurma hata değil "durduruldu" bildirimi olarak görünür, tam bir kez.
        let interrupts = state.items.filter { $0.kind == .notice(.interrupted) }
        #expect(interrupts.count == 1)
        #expect(!state.items.contains { if case .notice(.error) = $0.kind { true } else { false } })
        #expect(!state.items.contains { $0.isStreaming })
        #expect(state.isTurnActive == false)
    }

    @Test func historyReplayWithoutStreaming() {
        let jsonl = """
        {"type":"user","isSidechain":false,"cwd":"/Users/dev/proj","sessionId":"s1","message":{"role":"user","content":"Fix the bug"}}
        {"type":"assistant","isSidechain":false,"message":{"id":"msg_1","role":"assistant","content":[{"type":"thinking","thinking":"hmm"}]}}
        {"type":"assistant","isSidechain":false,"message":{"id":"msg_1","role":"assistant","content":[{"type":"tool_use","id":"tu_1","name":"Edit","input":{"file_path":"/a.swift","old_string":"a","new_string":"b"}}]}}
        {"type":"user","isSidechain":false,"message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"tu_1","content":"ok"}]}}
        {"type":"assistant","isSidechain":true,"message":{"id":"msg_sub","role":"assistant","content":[{"type":"text","text":"subagent noise"}]}}
        {"type":"user","isMeta":true,"message":{"role":"user","content":"<command-name>/clear</command-name>"}}
        {"type":"assistant","isSidechain":false,"message":{"id":"msg_2","role":"assistant","content":[{"type":"text","text":"Done."}]}}
        {"type":"summary","summary":"Bug fix"}
        """
        let state = HistoryLoader.load(data: Data(jsonl.utf8))
        #expect(state.items.count == 4)
        #expect(state.items[0].kind == .user("Fix the bug"))
        #expect(state.items[1].kind == .thinking("hmm", isStreaming: false))
        guard case .toolCall(let call) = state.items[2].kind else { Issue.record("araç yok"); return }
        #expect(call.status == .succeeded)
        #expect(call.summary == "/a.swift")
        #expect(state.items[3].kind == .assistantText("Done."))
    }

    @Test func processExitCancelsOpenTools() {
        var state = TranscriptState()
        state.appendLocalUserMessage("x")
        state.apply(.stream(.messageStart(messageId: "m1", usage: TokenUsage()), messageId: "m1", parentToolUseId: nil))
        state.apply(.stream(.blockStart(index: 0, kind: .toolUse(id: "t1", name: "Bash")), messageId: "m1", parentToolUseId: nil))
        state.apply(.stream(.blockDelta(index: 0, delta: .inputJSON("{\"command\":\"ls\"}")), messageId: "m1", parentToolUseId: nil))
        state.apply(.stream(.blockStop(index: 0), messageId: "m1", parentToolUseId: nil))
        guard case .toolCall(let running)? = state.item(id: "t1")?.kind else { Issue.record(); return }
        #expect(running.status == .running)
        #expect(running.summary == "ls")

        state.markProcessExited(error: "çöktü")
        guard case .toolCall(let cancelled)? = state.item(id: "t1")?.kind else { Issue.record(); return }
        #expect(cancelled.status == .cancelled)
        #expect(state.items.last?.kind == .notice(.error("çöktü")))
    }

    @Test func subagentEventsDoNotLeakIntoMainTranscript() {
        var state = TranscriptState()
        state.apply(.assistant(messageId: "m", content: [.toolUse(id: "task1", name: "Task", input: ["prompt": "go"])],
                               usage: TokenUsage(), parentToolUseId: nil))
        state.apply(.assistant(messageId: "sub", content: [.text("inner")], usage: TokenUsage(), parentToolUseId: "task1"))
        #expect(state.items.count == 1)
        guard case .toolCall(let call) = state.items[0].kind else { Issue.record(); return }
        #expect(call.subagentMessageCount == 1)
    }
}

@Suite("Kullanım metrikleri")
struct UsageMetricsTests {
    /// `result.total_cost_usd` süreç içinde kümülatiftir: aynı süreçteki ikinci `result` toplamı tekrar etmez.
    @Test func cumulativeCostIsNotDoubleCounted() throws {
        var state = TranscriptState()
        for m in try Fixture.lines("permission-then-interrupt") { state.apply(m) }
        #expect(abs(state.totalCostUSD - 0.00101003) < 1e-9)
    }

    /// Yeni süreç (ör. `--resume`) kendi kümülatifine sıfırdan başlar; session toplamına eklenir.
    @Test func costAccumulatesAcrossProcesses() throws {
        var state = TranscriptState()
        for m in try Fixture.lines("simple-turn") { state.apply(m) }
        state.markProcessExited(error: nil)
        for m in try Fixture.lines("simple-turn") { state.apply(m) }
        #expect(abs(state.totalCostUSD - 2 * 0.00060919) < 1e-9)
    }

    /// Geçmişten açılan session'da pencere bilinmez; doluluk uydurulmaz (eski varsayılan 200k halkayı %100 gösteriyordu).
    @Test func contextFractionIsUnknownUntilWindowIsReported() {
        var state = TranscriptState()
        state.apply(.assistant(messageId: "m", content: [.text("x")],
                               usage: TokenUsage(inputTokens: 1, outputTokens: 10, cacheReadInputTokens: 551_000),
                               parentToolUseId: nil))
        #expect(state.contextTokens == 551_011)
        #expect(state.contextWindow == nil)
        #expect(state.contextFraction == nil)
    }

    /// Alt ajan başka bir modelle çalışsa da pencere session'ın ana modelininkidir (eskiden en büyüğü seçiliyordu).
    @Test func contextWindowFollowsMainModel() throws {
        let initLine = #"{"type":"system","subtype":"init","session_id":"s","model":"main-model","tools":[]}"#
        let resultLine = #"{"type":"result","subtype":"success","is_error":false,"total_cost_usd":1,"usage":{},"modelUsage":{"main-model":{"contextWindow":200000},"sub-model":{"contextWindow":1000000}}}"#
        var state = TranscriptState()
        state.apply(try #require(InboundMessage.decode(line: Data(initLine.utf8))))
        state.apply(try #require(InboundMessage.decode(line: Data(resultLine.utf8))))
        #expect(state.contextWindow == 200_000)
    }

    /// Claude uygulamasındaki gibi 5 saatlik ve haftalık plan limitleri ayrı ayrı (gerçek CLI olayı, spike fixture'ı).
    @Test func planLimitWindowsAreParsed() throws {
        var state = TranscriptState()
        for m in try Fixture.lines("permission-then-interrupt") { state.apply(m) }
        let fiveHour = try #require(state.planLimits[.fiveHour])
        let weekly = try #require(state.planLimits[.sevenDay])
        #expect(fiveHour.utilization == 0.01)
        #expect(fiveHour.resetsAt == Date(timeIntervalSince1970: 1_792_698_600))
        #expect(weekly.utilization == 0.8)
        #expect(weekly.resetsAt == Date(timeIntervalSince1970: 1_792_846_800))
    }
}

@Suite("Geçmiş indeksi")
struct HistoryIndexTests {
    @Test func indexesProjectsDirectory() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "monster-history-\(UUID().uuidString)")
        let dir = root.appending(path: "-Users-dev-proj")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let lines = """
        {"type":"queue-operation"}
        {"type":"user","cwd":"/Users/dev/proj","gitBranch":"main","version":"2.1.308","message":{"role":"user","content":"Refactor the parser please"}}
        {"type":"assistant","message":{"id":"m","content":[{"type":"text","text":"ok"}]}}
        {"type":"ai-title","aiTitle":"Parser refactor"}
        """
        try Data(lines.utf8).write(to: dir.appending(path: "abc-123.jsonl"))
        try Data("{\"type\":\"queue-operation\"}\n".utf8).write(to: dir.appending(path: "empty.jsonl"))

        let entries = HistoryIndexer(root: root).scan()
        #expect(entries.count == 1)
        let entry = try #require(entries.first)
        #expect(entry.sessionId == "abc-123")
        #expect(entry.projectPath == "/Users/dev/proj")
        #expect(entry.projectName == "proj")
        #expect(entry.title == "Parser refactor")
        #expect(entry.firstPrompt == "Refactor the parser please")
        #expect(entry.gitBranch == "main")
    }
}
