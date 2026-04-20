import Foundation
@testable import Dahlia

#if canImport(Testing)
import Testing

struct AgentServiceTests {
    @Test
    func resolveLaunchArgumentsFallsBackToClaudeWhenBlank() {
        let arguments = AgentService.resolveLaunchArguments(from: "   ")

        #expect(arguments == ["claude"])
    }

    @Test
    func resolveLaunchArgumentsSplitsCommandAndArguments() {
        let arguments = AgentService.resolveLaunchArguments(from: "isaac --profile local")

        #expect(arguments == ["isaac", "--profile", "local"])
    }

    // MARK: - parseOutputLine

    @Test
    func parseOutputLineReturnsNilForInvalidJSON() {
        #expect(AgentService.parseOutputLine("not json") == nil)
        #expect(AgentService.parseOutputLine("{}") == nil)
    }

    @Test
    func parseOutputLineHandlesContentBlockDelta() {
        let json = #"{"type":"content_block_delta","delta":{"text":"Hello"}}"#
        guard case let .contentBlockDelta(text) = AgentService.parseOutputLine(json) else {
            Issue.record("Expected contentBlockDelta")
            return
        }
        #expect(text == "Hello")
    }

    @Test
    func parseOutputLineHandlesAssistantText() {
        let json = #"{"type":"assistant","message":{"content":[{"type":"text","text":"hi"}]}}"#
        guard case let .assistantText(text) = AgentService.parseOutputLine(json) else {
            Issue.record("Expected assistantText")
            return
        }
        #expect(text == "hi")
    }

    @Test
    func parseOutputLineHandlesToolUse() {
        let json = """
        {"type":"assistant","message":{"content":[{"type":"tool_use","name":"Read","id":"tu_1","input":{"file_path":"/a.swift"}}]}}
        """
        guard case let .assistantToolUses(toolUses) = AgentService.parseOutputLine(json) else {
            Issue.record("Expected assistantToolUses")
            return
        }
        #expect(toolUses.count == 1)
        #expect(toolUses[0].name == "Read")
        #expect(toolUses[0].id == "tu_1")
    }

    @Test
    func parseOutputLineHandlesToolResult() {
        let json = """
        {"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"tu_1","content":"ok","is_error":false}]}}
        """
        guard case let .toolResults(results) = AgentService.parseOutputLine(json) else {
            Issue.record("Expected toolResults")
            return
        }
        #expect(results.count == 1)
        #expect(results[0].toolUseId == "tu_1")
        #expect(results[0].content == "ok")
        #expect(results[0].isError == false)
    }

    @Test
    func parseOutputLineHandlesSystemInit() {
        let json = #"{"type":"system","subtype":"init"}"#
        guard case .systemInit = AgentService.parseOutputLine(json) else {
            Issue.record("Expected systemInit")
            return
        }
    }

    @Test
    func parseOutputLineHandlesResult() {
        let json = #"{"type":"result"}"#
        guard case .result = AgentService.parseOutputLine(json) else {
            Issue.record("Expected result")
            return
        }
    }

    @Test
    func parseOutputLineHandlesTextAndToolUseCombined() {
        let json = """
        {"type":"assistant","message":{"content":[
            {"type":"text","text":"Let me check."},
            {"type":"tool_use","name":"Read","id":"tu_2","input":{"file_path":"/b.swift"}}
        ]}}
        """
        guard case let .assistantToolUses(text, toolUses) = AgentService.parseOutputLine(json) else {
            Issue.record("Expected assistantToolUses")
            return
        }
        #expect(text == "Let me check.")
        #expect(toolUses.count == 1)
        #expect(toolUses[0].name == "Read")
    }

    @Test
    func parseOutputLineHandlesError() {
        let json = #"{"type":"error","error":{"message":"fail"}}"#
        guard case let .error(msg) = AgentService.parseOutputLine(json) else {
            Issue.record("Expected error")
            return
        }
        #expect(msg == "fail")
    }
}
#elseif canImport(XCTest)
import XCTest

final class AgentServiceTests: XCTestCase {
    func testResolveLaunchArgumentsFallsBackToClaudeWhenBlank() {
        XCTAssertEqual(AgentService.resolveLaunchArguments(from: "   "), ["claude"])
    }

    func testResolveLaunchArgumentsSplitsCommandAndArguments() {
        XCTAssertEqual(
            AgentService.resolveLaunchArguments(from: "isaac --profile local"),
            ["isaac", "--profile", "local"]
        )
    }

    func testParseOutputLineReturnsNilForInvalidJSON() {
        XCTAssertNil(AgentService.parseOutputLine("not json"))
        XCTAssertNil(AgentService.parseOutputLine("{}"))
    }

    func testParseOutputLineHandlesContentBlockDelta() {
        let json = #"{"type":"content_block_delta","delta":{"text":"Hello"}}"#
        guard case let .contentBlockDelta(text) = AgentService.parseOutputLine(json) else {
            XCTFail("Expected contentBlockDelta")
            return
        }
        XCTAssertEqual(text, "Hello")
    }

    func testParseOutputLineHandlesResult() {
        let json = #"{"type":"result"}"#
        guard case .result = AgentService.parseOutputLine(json) else {
            XCTFail("Expected result")
            return
        }
    }
}
#endif
