import XCTest
@testable import Remux

final class TmuxCommandPaletteActionTests: XCTestCase {
    func testAllActionsHaveNonEmptyTitleAndSubtitle() {
        for action in TmuxCommandPaletteAction.allCases {
            XCTAssertFalse(action.title.isEmpty, "Action \(action) should have title")
            XCTAssertFalse(action.subtitle.isEmpty, "Action \(action) should have subtitle")
            XCTAssertFalse(action.systemImage.isEmpty, "Action \(action) should have systemImage")
        }
    }

    func testCategoriesAreCovered() {
        let categories = Set(TmuxCommandPaletteAction.allCases.map(\.category))
        XCTAssertEqual(categories, Set(TmuxCommandPaletteCategory.allCases))
    }

    func testServerCommands() {
        XCTAssertEqual(
            TmuxCommandPaletteAction.saveSession.serverCommand,
            "run-shell ~/.dotfiles/scripts/tmux/tmux-async-save.sh"
        )
        XCTAssertEqual(
            TmuxCommandPaletteAction.restoreSession.serverCommand,
            "run-shell ~/.tmux/plugins/tmux-resurrect/scripts/restore.sh"
        )
        XCTAssertEqual(
            TmuxCommandPaletteAction.reloadConfig.serverCommand,
            "source-file ~/.tmux.conf"
        )
        XCTAssertNotNil(TmuxCommandPaletteAction.toggleAccordion.serverCommand)
        XCTAssertEqual(
            TmuxCommandPaletteAction.toggleStatusBar.serverCommand,
            "set-option -g status"
        )
        XCTAssertNil(TmuxCommandPaletteAction.newWindow.serverCommand)
    }

    func testByronProfileMapping() {
        XCTAssertEqual(TmuxCommandPaletteAction.byronClaude.byronProfile, .claude)
        XCTAssertEqual(TmuxCommandPaletteAction.byronWork.byronProfile, .work)
        XCTAssertEqual(TmuxCommandPaletteAction.byronPersonal.byronProfile, .personal)
        XCTAssertEqual(TmuxCommandPaletteAction.byronMuse.byronProfile, .muse)
        XCTAssertEqual(TmuxCommandPaletteAction.byronGrok.byronProfile, .grok)
        XCTAssertNil(TmuxCommandPaletteAction.saveSession.byronProfile)
    }

    func testQueryMatching() {
        XCTAssertTrue(TmuxCommandPaletteAction.saveSession.matches(query: "save"))
        XCTAssertTrue(TmuxCommandPaletteAction.saveSession.matches(query: "async"))
        XCTAssertTrue(TmuxCommandPaletteAction.newWindow.matches(query: "window"))
        XCTAssertTrue(TmuxCommandPaletteAction.newWindow.matches(query: "⌘T"))
        XCTAssertTrue(TmuxCommandPaletteAction.byronWork.matches(query: "work"))
        XCTAssertFalse(TmuxCommandPaletteAction.byronWork.matches(query: "nonexistent query"))
    }
}
