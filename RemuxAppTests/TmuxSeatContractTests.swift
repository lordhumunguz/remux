import Foundation
import XCTest

@testable import Remux

final class TmuxSeatContractTests: XCTestCase {
    // MARK: %exit classification

    func testBareExitClassifiesAsSeatTakenOnlyWithSeatContract() {
        for detail in [nil, "", "  \n"] {
            XCTAssertEqual(
                TmuxSeatContract.classify(exitDetail: detail, seatContractDetected: true),
                .seatTaken,
                "on a single-seat server a bare %exit is the detach path"
            )
            XCTAssertEqual(
                TmuxSeatContract.classify(exitDetail: detail, seatContractDetected: false),
                .serverExited,
                "on plain servers a bare %exit also covers kill-session/kill-server"
            )
        }
    }

    func testDetachReasonsClassifyAsSeatTakenRegardlessOfContract() {
        for detected in [true, false] {
            XCTAssertEqual(
                TmuxSeatContract.classify(
                    exitDetail: "detached (from session main)",
                    seatContractDetected: detected
                ),
                .seatTaken
            )
            XCTAssertEqual(
                TmuxSeatContract.classify(exitDetail: "detached", seatContractDetected: detected),
                .seatTaken
            )
            XCTAssertEqual(
                TmuxSeatContract.classify(
                    exitDetail: "detached and SIGHUP (from session main)",
                    seatContractDetected: detected
                ),
                .seatTaken
            )
        }
    }

    func testServerAndSessionExitsDoNotClassifyAsSeatTaken() {
        for detail in [
            "server exited",
            "server exited unexpectedly",
            "exited",
            "terminated",
            "lost tty",
            "something unexpected",
        ] {
            XCTAssertEqual(
                TmuxSeatContract.classify(exitDetail: detail, seatContractDetected: true),
                .serverExited,
                detail
            )
        }
    }

    func testSeatContractDetectionReadsClientAttachedHook() {
        XCTAssertTrue(TmuxSeatContract.detectsSeatContract(
            showHooksOutput: "client-attached detach-client\n"
        ))
        XCTAssertTrue(TmuxSeatContract.detectsSeatContract(
            showHooksOutput: "client-attached \"if -F '#{==:#{session_attached},1}' { detach-client }\"\n"
        ))
        XCTAssertFalse(TmuxSeatContract.detectsSeatContract(showHooksOutput: ""))
        XCTAssertFalse(TmuxSeatContract.detectsSeatContract(
            showHooksOutput: "client-attached display-message hello\n"
        ))
    }

    func testSeatTakenDisconnectReasonMapping() {
        XCTAssertEqual(
            TmuxSessionController.DetachReason.serverExited(nil)
                .terminalDisconnectReason(seatContractDetected: true).kind,
            .seatTaken
        )
        XCTAssertEqual(
            TmuxSessionController.DetachReason.serverExited("detached (from session main)")
                .terminalDisconnectReason(seatContractDetected: false).kind,
            .seatTaken
        )
        XCTAssertEqual(
            TmuxSessionController.DetachReason.serverExited(nil)
                .terminalDisconnectReason(seatContractDetected: false).kind,
            .remoteExit,
            "without the seat hook a bare %exit is a real exit"
        )
        XCTAssertEqual(
            TmuxSessionController.DetachReason.serverExited("server exited")
                .terminalDisconnectReason(seatContractDetected: true).kind,
            .remoteExit
        )
    }

    func testSeatTakenNeverReconnectsAutomatically() {
        let reason = TmuxSessionController.DetachReason.serverExited(nil)
            .terminalDisconnectReason(seatContractDetected: true)
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
