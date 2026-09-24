import UIKit
import XCTest
@testable import Remux

final class GhosttyHardwareShortcutTests: XCTestCase {
    func testResolveCommandShortcuts() {
        XCTAssertEqual(
            GhosttyHardwareKeyCommandFactory.resolve(input: "t", modifierFlags: .command),
            .newWindow
        )
        XCTAssertEqual(
            GhosttyHardwareKeyCommandFactory.resolve(input: "d", modifierFlags: .command),
            .splitPaneRight
        )
        XCTAssertEqual(
            GhosttyHardwareKeyCommandFactory.resolve(input: "d", modifierFlags: [.command, .shift]),
            .splitPaneDown
        )
        XCTAssertEqual(
            GhosttyHardwareKeyCommandFactory.resolve(input: "w", modifierFlags: .command),
            .closePane
        )
        XCTAssertEqual(
            GhosttyHardwareKeyCommandFactory.resolve(input: "[", modifierFlags: .command),
            .previousWindow
        )
        XCTAssertEqual(
            GhosttyHardwareKeyCommandFactory.resolve(input: "]", modifierFlags: .command),
            .nextWindow
        )
        XCTAssertEqual(
            GhosttyHardwareKeyCommandFactory.resolve(input: "z", modifierFlags: .command),
            .toggleZoom
        )
        XCTAssertEqual(
            GhosttyHardwareKeyCommandFactory.resolve(input: "o", modifierFlags: .command),
            .showSessions
        )
        XCTAssertEqual(
            GhosttyHardwareKeyCommandFactory.resolve(input: "r", modifierFlags: .command),
            .resumeAgent
        )
        XCTAssertEqual(
            GhosttyHardwareKeyCommandFactory.resolve(input: "j", modifierFlags: .command),
            .jumpToBlockedAgent
        )
        XCTAssertEqual(
            GhosttyHardwareKeyCommandFactory.resolve(input: "e", modifierFlags: .command),
            .toggleComposer
        )
        XCTAssertEqual(
            GhosttyHardwareKeyCommandFactory.resolve(input: "k", modifierFlags: .command),
            .clearScreen
        )
        XCTAssertEqual(
            GhosttyHardwareKeyCommandFactory.resolve(input: "p", modifierFlags: .command),
            .showCommandPalette
        )
    }

    func testResolveWindowIndexShortcuts() {
        for i in 1...9 {
            XCTAssertEqual(
                GhosttyHardwareKeyCommandFactory.resolve(input: "\(i)", modifierFlags: .command),
                .selectWindow(i - 1)
            )
        }
    }

    func testIgnoredKeyCombinations() {
        XCTAssertNil(GhosttyHardwareKeyCommandFactory.resolve(input: "a", modifierFlags: .command))
        XCTAssertNil(GhosttyHardwareKeyCommandFactory.resolve(input: "t", modifierFlags: .control))
        XCTAssertNil(GhosttyHardwareKeyCommandFactory.resolve(input: nil, modifierFlags: .command))
    }

    @MainActor
    func testMakeKeyCommandsCreatesExpectedEntries() {
        let commands = GhosttyHardwareKeyCommandFactory.makeCommands(
            action: #selector(DummyTarget.dummyAction)
        )
        XCTAssertGreaterThanOrEqual(commands.count, 21) // 12 standard + 9 window shortcuts
        XCTAssertTrue(commands.contains { $0.input == "t" && $0.modifierFlags == .command })
        XCTAssertTrue(commands.contains { $0.input == "d" && $0.modifierFlags == [.command, .shift] })
    }
}

private final class DummyTarget: NSObject {
    @objc func dummyAction() {}
}
