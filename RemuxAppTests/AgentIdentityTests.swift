import XCTest
@testable import Remux

final class AgentIdentityTests: XCTestCase {
    func testDetectsEachAgentFromCurrentCommand() {
        let cases: [(String, AgentIdentity)] = [
            ("claude", .claudeCode),
            ("codex", .codex),
            ("opencode", .opencode),
            ("kimi", .kimiCode),
            ("grok", .grok),
            ("goose", .goose),
            ("cursor", .cursor),
            ("gemini", .antigravity),
            ("antigravity", .antigravity),
            ("muse", .museCode),
        ]
        for (command, expected) in cases {
            XCTAssertEqual(
                AgentDetection.agent(forCommand: command),
                expected,
                "command \(command) should detect \(expected)"
            )
        }
    }

    func testDetectionIsCaseInsensitive() {
        XCTAssertEqual(AgentDetection.agent(forCommand: "Claude"), .claudeCode)
        XCTAssertEqual(AgentDetection.agent(forCommand: "CODEX"), .codex)
        XCTAssertEqual(AgentDetection.agent(forCommand: "Kimi"), .kimiCode)
    }

    func testDetectionToleratesVersionSuffixedCommands() {
        XCTAssertEqual(AgentDetection.agent(forCommand: "claude-2.1.37"), .claudeCode)
        XCTAssertEqual(AgentDetection.agent(forCommand: "kimi2"), .kimiCode)
        XCTAssertEqual(AgentDetection.agent(forCommand: "codex-cli"), .codex)
        XCTAssertEqual(AgentDetection.agent(forCommand: "node-claude-wrapper"), .claudeCode)
        XCTAssertEqual(AgentDetection.agent(forCommand: "/usr/local/bin/opencode"), .opencode)
    }

    func testDetectionReturnsNilForNonAgentCommands() {
        for command in ["", "zsh", "bash", "node", "nvim", "python3", "tmux", "ssh"] {
            XCTAssertNil(
                AgentDetection.agent(forCommand: command),
                "command \(command) should not detect an agent"
            )
        }
    }

    func testGlyphsAreDistinct() {
        let glyphs = AgentIdentity.allCases.map(\.glyph)
        XCTAssertEqual(Set(glyphs).count, glyphs.count)
    }

    func testAccentsAreDistinct() {
        let accents = AgentIdentity.allCases.map(\.accentRGB)
        let unique = Set(accents.map { "\($0.red)-\($0.green)-\($0.blue)" })
        XCTAssertEqual(unique.count, accents.count)
    }

    func testXterm256AccentConversionMatchesRegistryColors() {
        // claude_code soft orange (216), codex teal green (42), muse Meta pink (213)
        XCTAssertEqual(AgentIdentity.claudeCode.accentXtermIndex, 216)
        let orange = AgentIdentity.xterm256RGB(216)
        XCTAssertEqual(orange.red, 1.0, accuracy: 0.001)
        XCTAssertEqual(orange.green, 175.0 / 255.0, accuracy: 0.001)
        XCTAssertEqual(orange.blue, 135.0 / 255.0, accuracy: 0.001)
        let teal = AgentIdentity.xterm256RGB(42)
        XCTAssertEqual(teal.red, 0.0, accuracy: 0.001)
        XCTAssertEqual(teal.green, 215.0 / 255.0, accuracy: 0.001)
        XCTAssertEqual(teal.blue, 135.0 / 255.0, accuracy: 0.001)
        // grok light gray (250) lands on the grayscale ramp
        let gray = AgentIdentity.xterm256RGB(250)
        XCTAssertEqual(gray.red, gray.green)
        XCTAssertEqual(gray.green, gray.blue)
        XCTAssertEqual(gray.red, 188.0 / 255.0, accuracy: 0.001)
    }

    func testResumeCommands() {
        XCTAssertEqual(AgentIdentity.claudeCode.resumeCommand, "claude --resume")
        XCTAssertEqual(AgentIdentity.codex.resumeCommand, "codex resume")
        XCTAssertEqual(AgentIdentity.opencode.resumeCommand, "opencode --continue")
        XCTAssertEqual(AgentIdentity.kimiCode.resumeCommand, "kimi -S")
        XCTAssertEqual(AgentIdentity.grok.resumeCommand, "grok --resume")
        XCTAssertEqual(AgentIdentity.museCode.resumeCommand, "muse resume")
        XCTAssertNil(AgentIdentity.cursor.resumeCommand)
        XCTAssertNil(AgentIdentity.antigravity.resumeCommand)
        XCTAssertNil(AgentIdentity.goose.resumeCommand)
    }

    func testAgentWindowCycleAdvancesToNextAgentWindow() {
        XCTAssertEqual(
            AgentWindowCycle.nextAgentWindowIndex(
                hasAgentByWindow: [false, true, false, true],
                currentIndex: 1
            ),
            3
        )
    }

    func testAgentWindowCycleWrapsAround() {
        XCTAssertEqual(
            AgentWindowCycle.nextAgentWindowIndex(
                hasAgentByWindow: [true, false, false],
                currentIndex: 0
            ),
            0
        )
        XCTAssertEqual(
            AgentWindowCycle.nextAgentWindowIndex(
                hasAgentByWindow: [true, false, true],
                currentIndex: 2
            ),
            0
        )
    }

    func testAgentWindowCycleWithoutCurrentStartsAtFirstAgentWindow() {
        XCTAssertEqual(
            AgentWindowCycle.nextAgentWindowIndex(
                hasAgentByWindow: [false, true],
                currentIndex: nil
            ),
            1
        )
    }

    func testAgentWindowCycleReturnsNilWithoutAgents() {
        XCTAssertNil(
            AgentWindowCycle.nextAgentWindowIndex(
                hasAgentByWindow: [false, false],
                currentIndex: 0
            )
        )
        XCTAssertNil(
            AgentWindowCycle.nextAgentWindowIndex(
                hasAgentByWindow: [],
                currentIndex: nil
            )
        )
    }
}
