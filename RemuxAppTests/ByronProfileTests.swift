import XCTest
@testable import Remux

final class ByronProfileTests: XCTestCase {
    func testByronProfileCommandsAndExecutionLines() {
        XCTAssertEqual(ByronProfile.work.command, "byron c work")
        XCTAssertEqual(ByronProfile.work.executionLine, "byron c work\n")
        XCTAssertEqual(ByronProfile.work.displayName, "Claude (work)")
        XCTAssertEqual(ByronProfile.work.shortLabel, "work")

        XCTAssertEqual(ByronProfile.personal.command, "byron c personal")
        XCTAssertEqual(ByronProfile.personal.executionLine, "byron c personal\n")

        XCTAssertEqual(ByronProfile.muse.command, "byron muse")
        XCTAssertEqual(ByronProfile.muse.executionLine, "byron muse\n")

        XCTAssertEqual(ByronProfile.grok.command, "byron grok")
        XCTAssertEqual(ByronProfile.grok.executionLine, "byron grok\n")

        XCTAssertEqual(ByronProfile.claude.command, "byron")
        XCTAssertEqual(ByronProfile.claude.executionLine, "byron\n")
    }

    func testByronLaunchActions() {
        XCTAssertEqual(ByronLaunchAction.inCurrentPane.title, "Run in Current Pane")
        XCTAssertEqual(ByronLaunchAction.splitRight.title, "Split Right & Run")
        XCTAssertEqual(ByronLaunchAction.splitDown.title, "Split Down & Run")
        XCTAssertEqual(ByronLaunchAction.newWindow.title, "New Window & Run")
    }
}
