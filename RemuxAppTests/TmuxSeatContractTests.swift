import Foundation
import XCTest

@testable import Remux

final class TmuxSeatContractTests: XCTestCase {
    // MARK: %exit classification

    func testBareExitClassifiesAsSeatTaken() {
        XCTAssertEqual(TmuxSeatContract.classify(exitDetail: nil), .seatTaken)
        XCTAssertEqual(TmuxSeatContract.classify(exitDetail: ""), .seatTaken)
        XCTAssertEqual(TmuxSeatContract.classify(exitDetail: "  \n"), .seatTaken)
    }

    func testDetachReasonsClassifyAsSeatTaken() {
        XCTAssertEqual(
            TmuxSeatContract.classify(exitDetail: "detached (from session main)"),
            .seatTaken
        )
        XCTAssertEqual(
            TmuxSeatContract.classify(exitDetail: "detached"),
            .seatTaken
        )
        XCTAssertEqual(
            TmuxSeatContract.classify(exitDetail: "detached and SIGHUP (from session main)"),
            .seatTaken
        )
    }

    func testServerAndSessionExitsDoNotClassifyAsSeatTaken() {
        XCTAssertEqual(
            TmuxSeatContract.classify(exitDetail: "server exited"),
            .serverExited
        )
        XCTAssertEqual(
            TmuxSeatContract.classify(exitDetail: "server exited unexpectedly"),
            .serverExited
        )
        XCTAssertEqual(
            TmuxSeatContract.classify(exitDetail: "exited"),
            .serverExited
        )
        XCTAssertEqual(
            TmuxSeatContract.classify(exitDetail: "terminated"),
            .serverExited
        )
        XCTAssertEqual(
            TmuxSeatContract.classify(exitDetail: "lost tty"),
            .serverExited
        )
        XCTAssertEqual(
            TmuxSeatContract.classify(exitDetail: "something unexpected"),
            .serverExited
        )
    }

    func testSeatTakenDisconnectReasonMapping() {
        XCTAssertEqual(
            TmuxSessionController.DetachReason.serverExited(nil).terminalDisconnectReason.kind,
            .seatTaken
        )
        XCTAssertEqual(
            TmuxSessionController.DetachReason.serverExited("detached (from session main)")
                .terminalDisconnectReason.kind,
            .seatTaken
        )
        XCTAssertEqual(
            TmuxSessionController.DetachReason.serverExited("server exited")
                .terminalDisconnectReason.kind,
            .remoteExit
        )
    }

    func testSeatTakenNeverReconnectsAutomatically() {
        let reason = TmuxSessionController.DetachReason.serverExited(nil).terminalDisconnectReason
        XCTAssertFalse(reason.allowsAutomaticReconnect)
    }

    // MARK: list-clients occupancy

    func testOccupancyDetectsInteractiveViewer() {
        XCTAssertTrue(TmuxSeatContract.hasInteractiveViewer(listClientsOutput: "0\n"))
        XCTAssertTrue(TmuxSeatContract.hasInteractiveViewer(listClientsOutput: "1\n0\n"))
        XCTAssertTrue(TmuxSeatContract.hasInteractiveViewer(listClientsOutput: " 0 \n"))
    }

    func testOccupancyIgnoresControlOnlyClientsAndEmptyOutput() {
        XCTAssertFalse(TmuxSeatContract.hasInteractiveViewer(listClientsOutput: "1\n"))
        XCTAssertFalse(TmuxSeatContract.hasInteractiveViewer(listClientsOutput: "1\n1\n1\n"))
        XCTAssertFalse(TmuxSeatContract.hasInteractiveViewer(listClientsOutput: ""))
        XCTAssertFalse(TmuxSeatContract.hasInteractiveViewer(listClientsOutput: "\n\n"))
    }

    // MARK: Accordion option parsing

    func testAccordionParsesOnlyLiteralOn() {
        XCTAssertTrue(TmuxResponsiveAccordion.isEnabled(showOptionOutput: "on"))
        XCTAssertTrue(TmuxResponsiveAccordion.isEnabled(showOptionOutput: "on\n"))
        XCTAssertTrue(TmuxResponsiveAccordion.isEnabled(showOptionOutput: " on \n"))
        XCTAssertFalse(TmuxResponsiveAccordion.isEnabled(showOptionOutput: "off"))
        XCTAssertFalse(TmuxResponsiveAccordion.isEnabled(showOptionOutput: "1"))
        XCTAssertFalse(TmuxResponsiveAccordion.isEnabled(showOptionOutput: ""))
        XCTAssertFalse(TmuxResponsiveAccordion.isEnabled(showOptionOutput: "yes"))
    }
}
