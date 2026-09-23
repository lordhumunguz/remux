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

    func testResolvesAgentIdentityAndProfileFromToolString() {
        let cases: [(tool: String, expectedIdentity: AgentIdentity, expectedProfile: String?, expectedByronName: String, expectedCompact: String)] = [
            ("claude:work", .claudeCode, "work", "claude:work", "work"),
            ("claude:personal", .claudeCode, "personal", "claude:personal", "personal"),
            ("claude_code", .claudeCode, nil, "claude_code", "claude_code"),
            ("muse", .museCode, nil, "muse", "muse"),
            ("muse_code", .museCode, nil, "muse_code", "muse_code"),
            ("grok", .grok, nil, "grok", "grok"),
            ("grok_build", .grok, nil, "grok_build", "grok_build"),
            ("codex", .codex, nil, "codex", "codex"),
            ("opencode", .opencode, nil, "opencode", "opencode"),
            ("kimi:research", .kimiCode, "research", "kimi:research", "research"),
            ("kimi_code", .kimiCode, nil, "kimi_code", "kimi_code"),
            ("cursor", .cursor, nil, "cursor", "cursor"),
            ("antigravity:custom", .antigravity, "custom", "antigravity:custom", "custom"),
            ("goose", .goose, nil, "goose", "goose"),
        ]

        for c in cases {
            let res = AgentDetection.resolve(tool: c.tool, command: "node")
            XCTAssertNotNil(res, "Tool \(c.tool) should resolve")
            XCTAssertEqual(res?.identity, c.expectedIdentity)
            XCTAssertEqual(res?.profile, c.expectedProfile)
            XCTAssertEqual(res?.byronProfileName, c.expectedByronName)
            XCTAssertEqual(res?.compactLabel, c.expectedCompact)
            if let profile = c.expectedProfile {
                XCTAssertEqual(res?.glyphWithProfile, "\(c.expectedIdentity.glyph) \(profile)")
            }
        }
    }

    func testResolveFallsBackToCommandDetection() {
        let fromCommand = AgentDetection.resolve(tool: nil, command: "claude-2.1.37")
        XCTAssertEqual(fromCommand?.identity, .claudeCode)
        XCTAssertNil(fromCommand?.profile)
        XCTAssertEqual(fromCommand?.byronProfileName, "Claude Code")

        let fromEmptyTool = AgentDetection.resolve(tool: "", command: "codex-cli")
        XCTAssertEqual(fromEmptyTool?.identity, .codex)

        let unresolvableToolFallback = AgentDetection.resolve(tool: "unknown_wrapper", command: "grok")
        XCTAssertEqual(unresolvableToolFallback?.identity, .grok)

        let nonAgent = AgentDetection.resolve(tool: nil, command: "python3 main.py")
        XCTAssertNil(nonAgent)
    }

    func testProfileExtraction() {
        XCTAssertEqual(AgentDetection.profile(forTool: "claude:work"), "work")
        XCTAssertEqual(AgentDetection.profile(forTool: "antigravity:personal"), "personal")
        XCTAssertNil(AgentDetection.profile(forTool: "claude:"))
        XCTAssertNil(AgentDetection.profile(forTool: "muse"))
        XCTAssertNil(AgentDetection.profile(forTool: ""))
    }

    func testQuotaPillColorsAndThresholds() {
        let pillLow = TmuxAgentQuotaPill(percent: 36)
        XCTAssertEqual(pillLow.foregroundColor, TerminalSelectionSheetPalette.secondary)

        let pillAmber75 = TmuxAgentQuotaPill(percent: 75)
        XCTAssertEqual(pillAmber75.foregroundColor, TmuxAgentStatePalette.working)

        let pillAmber89 = TmuxAgentQuotaPill(percent: 89)
        XCTAssertEqual(pillAmber89.foregroundColor, TmuxAgentStatePalette.working)

        let pillRed90 = TmuxAgentQuotaPill(percent: 90)
        XCTAssertEqual(pillRed90.foregroundColor, TmuxAgentStatePalette.blocked)

        let pillRed95 = TmuxAgentQuotaPill(percent: 95)
        XCTAssertEqual(pillRed95.foregroundColor, TmuxAgentStatePalette.blocked)
    }

    func testWhitespaceTrimmingInTools() {
        let res = AgentDetection.resolve(tool: "  claude:work  ", command: "zsh")
        XCTAssertEqual(res?.identity, .claudeCode)
        XCTAssertEqual(res?.profile, "work")
        XCTAssertEqual(res?.byronProfileName, "claude:work")
        XCTAssertEqual(res?.compactLabel, "work")

        let colonSpaces = AgentDetection.resolve(tool: "claude : work", command: "zsh")
        XCTAssertEqual(colonSpaces?.identity, .claudeCode)
        XCTAssertEqual(colonSpaces?.profile, "work")
    }

    func testAgentProfilePillViewResolutionCompactVersusFull() {
        let profiled = AgentDetection.resolve(tool: "claude:work", command: "node")!
        XCTAssertEqual(profiled.byronProfileName, "claude:work")
        XCTAssertEqual(profiled.compactLabel, "work")
        XCTAssertEqual(profiled.glyphWithProfile, "✦ work")

        let plain = AgentDetection.resolve(tool: "muse", command: "node")!
        XCTAssertEqual(plain.byronProfileName, "muse")
        XCTAssertEqual(plain.compactLabel, "muse")
        XCTAssertEqual(plain.glyphWithProfile, "◈ muse")

        let fallback = AgentDetection.resolve(tool: nil, command: "grok")!
        XCTAssertEqual(fallback.byronProfileName, "Grok")
        XCTAssertEqual(fallback.compactLabel, "Grok")
        XCTAssertEqual(fallback.glyphWithProfile, "𝕏 Grok")
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
