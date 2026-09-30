import XCTest
@testable import Remux

final class ByronProfileTests: XCTestCase {
    func testByronProfileCommandsAndExecutionLines() {
        XCTAssertEqual(ByronProfile.work.command, "cc work")
        XCTAssertEqual(ByronProfile.work.executionLine, "cc work\n")
        XCTAssertEqual(ByronProfile.work.displayName, "Claude (work)")
        XCTAssertEqual(ByronProfile.work.shortLabel, "work")

        XCTAssertEqual(ByronProfile.personal.command, "cc personal")
        XCTAssertEqual(ByronProfile.personal.executionLine, "cc personal\n")

        XCTAssertEqual(ByronProfile.muse.command, "muse")
        XCTAssertEqual(ByronProfile.muse.executionLine, "muse\n")

        XCTAssertEqual(ByronProfile.grok.command, "grok")
        XCTAssertEqual(ByronProfile.grok.executionLine, "grok\n")

        XCTAssertEqual(ByronProfile.claude.command, "cc")
        XCTAssertEqual(ByronProfile.claude.executionLine, "cc\n")
    }

    func testByronLaunchActions() {
        XCTAssertEqual(ByronLaunchAction.inCurrentPane.title, "Run in Current Pane")
        XCTAssertEqual(ByronLaunchAction.splitRight.title, "Split Right & Run")
        XCTAssertEqual(ByronLaunchAction.splitDown.title, "Split Down & Run")
        XCTAssertEqual(ByronLaunchAction.newWindow.title, "New Window & Run")
    }
}
