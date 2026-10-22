import Foundation
import Testing
@testable import MonsterCore

/// Fixture'lar CLI 2.1.308 ile G2 spike'ında yakalanan gerçek akışlardır (yollar/id'ler anonimleştirildi).
enum Fixture {
    static func lines(_ name: String) throws -> [InboundMessage] {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "ndjson", subdirectory: "Fixtures"))
        var splitter = NDJSONLineSplitter()
        let data = try Data(contentsOf: url)
        var lines = splitter.append(data)
        if let last = splitter.finish() { lines.append(last) }
        return lines.compactMap { InboundMessage.decode(line: $0) }
    }
}

@Suite("stream-json protokolü")
struct ProtocolTests {
    @Test func splitterHandlesArbitraryChunking() {
        var splitter = NDJSONLineSplitter()
        let payload = Data("{\"a\":1}\n{\"b\":\r\n2}\n\n{\"c\":3}".utf8)
        var out: [Data] = []
        for byte in payload { out += splitter.append(Data([byte])) }
        if let last = splitter.finish() { out.append(last) }
        #expect(out.map { String(decoding: $0, as: UTF8.self) } == ["{\"a\":1}", "{\"b\":", "2}", "{\"c\":3}"])
    }

    @Test func decodesSimpleTurn() throws {
        let messages = try Fixture.lines("simple-turn")
        guard case .systemInit(let info)? = messages.first(where: { if case .systemInit = $0 { true } else { false } }) else {
            Issue.record("init yok"); return
        }
        #expect(info.model == "claude-haiku-5-5")
        #expect(info.cliVersion == "2.1.308")

        let deltas = messages.compactMap { message -> String? in
            if case .stream(.blockDelta(_, .text(let t)), _, _) = message { return t }
            return nil
        }
        #expect(deltas.joined() == "Hello there friend!")

        guard case .result(let result)? = messages.last else { Issue.record("result yok"); return }
        #expect(result.subtype == "success")
        #expect(result.isError == false)
        #expect(result.resultText == "Hello there friend!")
        #expect((result.totalCostUSD ?? 0) > 0)
        #expect(result.contextWindows == ["claude-haiku-5-5": 1_000_000])
    }

    @Test func decodesPermissionRequest() throws {
        let messages = try Fixture.lines("permission-then-interrupt")
        let requests = messages.compactMap { m -> PermissionRequest? in
            if case .permissionRequest(let r) = m { return r }
            return nil
        }
        #expect(requests.count == 1)
        let request = try #require(requests.first)
        #expect(request.toolName == "Write")
        #expect(request.input["file_path"]?.stringValue == "/Users/dev/proj/spike/b.txt")
        #expect(request.toolUseId?.hasPrefix("toolu_") == true)
        #expect(request.suggestions.first?["mode"]?.stringValue == "acceptEdits")
    }

    @Test func unknownTypesAreTolerated() {
        #expect(InboundMessage.decode(line: Data("{\"type\":\"brand_new_event\",\"x\":1}".utf8)) == .unknown(type: "brand_new_event"))
        #expect(InboundMessage.decode(line: Data("not json".utf8)) == nil)
        if case .system(let subtype)? = InboundMessage.decode(line: Data("{\"type\":\"system\",\"subtype\":\"future\"}".utf8)) {
            #expect(subtype == "future")
        } else {
            Issue.record("system/future çözülmedi")
        }
    }

    @Test func encodesUserMessageAsSingleLine() throws {
        let line = OutboundMessage.userText("satır1\nsatır2 \"tırnak\" ; rm -rf ~").encodedLine()
        #expect(line.last == 0x0A)
        #expect(line.dropLast().contains(0x0A) == false)
        let json = try JSONValue.parse(Data(line.dropLast()))
        #expect(json["type"]?.stringValue == "user")
        #expect(json["message"]?["content"]?.stringValue == "satır1\nsatır2 \"tırnak\" ; rm -rf ~")
    }

    @Test func encodesPermissionDecisions() throws {
        let request = PermissionRequest(requestId: "r1", toolName: "Write", input: ["file_path": "/x", "n": 3],
                                        toolUseId: "t1", suggestions: [["type": "setMode", "mode": "acceptEdits", "destination": "session"]])

        let allow = OutboundMessage.permissionDecision(requestId: "r1", decision: .allowOnce, request: request).json
        #expect(allow["type"]?.stringValue == "control_response")
        #expect(allow["response"]?["request_id"]?.stringValue == "r1")
        #expect(allow["response"]?["response"]?["behavior"]?.stringValue == "allow")
        #expect(allow["response"]?["response"]?["updatedInput"]?["n"]?.intValue == 3)
        #expect(allow["response"]?["response"]?["updatedPermissions"] == nil)

        let session = OutboundMessage.permissionDecision(requestId: "r1", decision: .allowForSession, request: request).json
        #expect(session["response"]?["response"]?["updatedPermissions"]?[0]?["mode"]?.stringValue == "acceptEdits")

        let deny = OutboundMessage.permissionDecision(requestId: "r1", decision: .deny(message: "hayır"), request: request).json
        #expect(deny["response"]?["response"]?["behavior"]?.stringValue == "deny")
        #expect(deny["response"]?["response"]?["message"]?.stringValue == "hayır")
    }

    @Test func integersRoundTrip() throws {
        let value = try JSONValue.parse("{\"a\":5,\"b\":1.5,\"c\":[true,null]}")
        #expect(value.compactString(sortedKeys: true) == "{\"a\":5,\"b\":1.5,\"c\":[true,null]}")
    }
}

@Suite("Başlatma argümanları")
struct LaunchConfigurationTests {
    @Test func chatModeIsReadOnly() {
        let config = LaunchConfiguration(mode: .chat, workingDirectory: URL(filePath: "/tmp/monster-chat"), permissionMode: .fullAccess)
        let args = config.arguments
        #expect(args.contains("--tools"))
        let tools = args[args.firstIndex(of: "--tools")! + 1]
        #expect(!tools.contains("Bash") && !tools.contains("Write") && !tools.contains("Edit"))
        // Sohbet modunda Full access seçilse bile CLI'a "default" gider ve bypass seçeneği açılmaz.
        #expect(args[args.firstIndex(of: "--permission-mode")! + 1] == "default")
        #expect(!args.contains("--allow-dangerously-skip-permissions"))
    }

    @Test func codeModeResume() {
        let config = LaunchConfiguration(mode: .code, workingDirectory: URL(filePath: "/p"), model: "opus", effort: .high,
                                         permissionMode: .autoEdit, resumeSessionId: "abc", newSessionId: "ignored")
        let args = config.arguments
        #expect(args.contains("--resume") && args.contains("abc"))
        #expect(!args.contains("--session-id"))
        #expect(args[args.firstIndex(of: "--permission-mode")! + 1] == "acceptEdits")
        #expect(args[args.firstIndex(of: "--effort")! + 1] == "high")
        #expect(args.contains("--permission-prompt-tool"))
    }

    @Test func userTextNeverInArguments() {
        // Kullanıcı metni yalnızca stdin'den gider; argüman listesinde serbest metin alanı yoktur.
        let config = LaunchConfiguration(mode: .code, workingDirectory: URL(filePath: "/p; rm -rf ~"))
        #expect(!config.arguments.contains { $0.contains("rm -rf") })
    }
}
