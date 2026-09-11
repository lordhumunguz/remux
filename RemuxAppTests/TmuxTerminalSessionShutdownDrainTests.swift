import GhosttyKit
import XCTest
import UIKit

@testable import Remux

@MainActor
final class TmuxTerminalSessionShutdownDrainTests: XCTestCase {
    func testRetainedTerminalHandoffPromotesHydratingPaneToLive() async throws {
        let runtime = try GhosttyKitRuntime()
        let session = makeSession(runtime: runtime)
        session.handleTopology(snapshot(phase: .hydrating))

        XCTAssertTrue(session.livePaneIDs.isEmpty)
        session.handlePaneTerminalForTesting(10)
        XCTAssertEqual(session.livePaneIDs, [10])

        session.handlePaneRemovedForTesting(10)
        XCTAssertTrue(session.livePaneIDs.isEmpty)
        await session.shutdown()
    }

    func testRetainedTerminalHandoffForUnknownPaneIsIgnored() async throws {
        let runtime = try GhosttyKitRuntime()
        let session = makeSession(runtime: runtime)
        session.handleTopology(snapshot(phase: .hydrating))

        session.handlePaneTerminalForTesting(99)

        XCTAssertTrue(session.livePaneIDs.isEmpty)
        await session.shutdown()
    }

    func testLiveTopologySeedsPickerEligibilityWithoutHandoff() async throws {
        let runtime = try GhosttyKitRuntime()
        let session = makeSession(runtime: runtime)

        session.handleTopology(snapshot(phase: .live))

        XCTAssertEqual(session.livePaneIDs, [10])
        await session.shutdown()
    }

    func testTopologyRemovalReconcilesLivePaneSet() async throws {
        let runtime = try GhosttyKitRuntime()
        let session = makeSession(runtime: runtime)
        session.handleTopology(snapshot(phase: .live))

        session.handleTopology(emptySnapshot())

        XCTAssertTrue(session.livePaneIDs.isEmpty)
        await session.shutdown()
    }

    func testShutdownCompletesWithoutNativePaneHandoff() async throws {
        let runtime = try GhosttyKitRuntime()
        let session = makeSession(runtime: runtime)
        session.handleTopology(snapshot(phase: .hydrating))

        await session.shutdown()

        XCTAssertTrue(session.livePaneIDs.isEmpty)
    }

    func testInitialRetainFailureWithoutSurfaceIsRepairableAndPaneScoped() async throws {
        let runtime = try GhosttyKitRuntime()
        let session = makeSession(runtime: runtime)
        session.handleTopology(twoPaneSnapshot(activePaneID: 10))
        session.handleStateForTesting(.ready)
        XCTAssertEqual(session.selectedPanePresentation, .pending)

        session.handleRendererFailureForTesting(11)
        XCTAssertEqual(session.selectedPanePresentation, .pending)
        session.handleTopology(twoPaneSnapshot(activePaneID: 11))
        guard case .failed(let reason) = session.selectedPanePresentation else {
            return XCTFail("selected missing surface must expose repair")
        }
        XCTAssertEqual(reason.kind, .runtime)
        session.handlePaneRemovedForTesting(11)
        XCTAssertEqual(session.selectedPanePresentation, .pending)
        await session.shutdown()
    }

    func testCreationFailureKeepsHandoffOwnedUntilReportedAndDoesNotRetryOnTopology() async throws {
        let runtime = try GhosttyKitRuntime()
        var complete: (@MainActor (Result<TmuxPaneSurface, TmuxPaneSurface.CreateError>) -> Void)?
        weak var handedOff: TmuxSessionController.RetainedPaneTerminal?
        var creations = 0
        let session = TmuxTerminalSession(
            app: runtime.appHandleForTesting,
            transport: DeterministicTmuxControlTransport(chunks: []),
            baseSurfaceConfig: { runtime.makeTmuxBaseSurfaceConfig() },
            paneViewTheme: { .remuxDark },
            createPaneSurface: { _, _, terminal, _, _, _, _, completion in
                creations += 1
                handedOff = terminal
                complete = completion
            }
        )
        let measurement = try XCTUnwrap(runtime.measureTmuxViewportLayout(
            size: CGSize(width: 390, height: 600), scale: UIScreen.main.scale
        ))
        session.updateViewportMeasurement(measurement)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            session.controller.start(initialSize: .init(cols: 83, rows: 44)) {
                continuation.resume(with: $0)
            }
        }
        session.controller.pump(Data("%begin 1 1 0\n%end 1 1 0\n%session-changed $42 main\n".utf8))
        await drain(session.controller)
        session.controller.pump(Data((
            "%begin 2 2 1\n3.1\n%end 2 2 1\n%begin 3 3 1\n%end 3 3 1\n"
            + "%begin 4 4 1\n$42 @0 1 %0 83 44 b7dd,83x44,0,0,0 b7dd,83x44,0,0,0 test\n%end 4 4 1\n"
        ).utf8))
        await drain(session.controller)
        // Protocol success and topology alone are not presentation success.
        XCTAssertEqual(session.state, .ready)
        XCTAssertEqual(session.selectedPanePresentation, .pending)
        let hydration = (5...9).map { "%begin \($0) \($0) 1\n%end \($0) \($0) 1\n" }.joined()
        session.controller.pump(Data(hydration.utf8))
        await drain(session.controller)
        XCTAssertEqual(creations, 1)
        XCTAssertNotNil(handedOff, "session must own the terminal during asynchronous creation")
        XCTAssertEqual(session.creatingPaneIDsForTesting, [0])
        session.handleTopology(try XCTUnwrap(session.topology))
        XCTAssertEqual(creations, 1)
        XCTAssertNotNil(handedOff, "reconciliation during creation must not consume pending ownership")
        complete?(.failure(.registrationFailed(.paneUnknown)))
        complete = nil
        XCTAssertNil(handedOff, "reported terminal failure releases the pending ownership")
        guard case .failed = session.selectedPanePresentation else {
            return XCTFail("initial registration failure must expose repair")
        }
        session.handleTopology(try XCTUnwrap(session.topology))
        session.updateViewportMeasurement(measurement)
        XCTAssertEqual(creations, 1, "ordinary topology/output must not create unbounded retries")
        XCTAssertTrue(session.creatingPaneIDsForTesting.isEmpty)
        await session.shutdown()
    }

    func testBlankFrameRequiresAttachmentAndReplacementTimeoutPreservesRecoveryImage() async throws {
        let runtime = try GhosttyKitRuntime()
        let session = TmuxTerminalSession(
            app: runtime.appHandleForTesting,
            transport: DeterministicTmuxControlTransport(chunks: []),
            baseSurfaceConfig: { runtime.makeTmuxBaseSurfaceConfig() },
            paneViewTheme: { .remuxDark }
        )
        let measurement = try XCTUnwrap(runtime.measureTmuxViewportLayout(
            size: CGSize(width: 390, height: 600), scale: UIScreen.main.scale
        ))
        session.updateViewportMeasurement(measurement)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            session.controller.start(initialSize: .init(cols: 83, rows: 44)) {
                continuation.resume(with: $0)
            }
        }
        session.controller.pump(Data("%begin 1 1 0\n%end 1 1 0\n%session-changed $42 main\n".utf8))
        await drain(session.controller)
        session.controller.pump(Data((
            "%begin 2 2 1\n3.1\n%end 2 2 1\n%begin 3 3 1\n%end 3 3 1\n"
            + "%begin 4 4 1\n$42 @0 1 %0 83 44 b7dd,83x44,0,0,0 b7dd,83x44,0,0,0 test\n%end 4 4 1\n"
        ).utf8))
        await drain(session.controller)
        let hydration = (5...9).map { "%begin \($0) \($0) 1\n%end \($0) \($0) 1\n" }.joined()
        session.controller.pump(Data(hydration.utf8))
        for _ in 0..<3 { await drain(session.controller) }
        let surface = try XCTUnwrap(session.surfacesByPaneID[0])
        let managed = surface.screenSurface(id: UUID())
        XCTAssertEqual(surface.presentation, .pending, "an unattached renderer is not ready")

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 600))
        let viewController = UIViewController()
        window.rootViewController = viewController
        viewController.view.addSubview(surface.view)
        window.isHidden = false
        defer { window.isHidden = true }
        for _ in 0..<100 where surface.presentation != .ready {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(surface.presentation, .ready, "empty terminal contents still publish a valid frame")
        surface.view.removeFromSuperview()
        XCTAssertEqual(surface.presentation, .pending, "detachment invalidates readiness even after a frame")
        viewController.view.addSubview(surface.view)
        XCTAssertEqual(surface.presentation, .ready)
        let metrics = try XCTUnwrap(measurement.displayMetrics(columns: 83, rows: 44))
        let recovered = await withCheckedContinuation { continuation in
            surface.replaceRenderer(
                baseConfig: runtime.makeTmuxBaseSurfaceConfig(), metrics: metrics, theme: .remuxDark
            ) { continuation.resume(returning: $0) }
        }
        XCTAssertEqual(recovered, .replaced, "expected \(metrics), actual \(managed.controlSurface.currentSize())")
        XCTAssertEqual(surface.presentation, .ready)
        XCTAssertTrue(managed.rendererIsAvailable)
        XCTAssertNil(managed.rendererRecoverySnapshot)

        surface.suppressReplacementPublicationForTesting = true
        let result = await withCheckedContinuation { continuation in
            surface.replaceRenderer(
                baseConfig: runtime.makeTmuxBaseSurfaceConfig(), metrics: metrics, theme: .remuxDark
            ) { continuation.resume(returning: $0) }
        }
        XCTAssertEqual(result, .failed, "a replacement without a frame must not succeed")
        XCTAssertFalse(managed.rendererIsAvailable)
        XCTAssertNotNil(managed.rendererRecoverySnapshot, "retain the last known frame until repair succeeds")
        XCTAssertNotEqual(surface.presentation, .ready)
        await session.shutdown()
    }

    private func drain(_ controller: TmuxSessionController) async {
        await withCheckedContinuation { continuation in
            controller.queue.async {
                DispatchQueue.main.async { continuation.resume() }
            }
        }
    }

    private func makeSession(runtime: GhosttyKitRuntime) -> TmuxTerminalSession {
        TmuxTerminalSession(
            app: runtime.appHandleForTesting,
            transport: DeterministicTmuxControlTransport(chunks: []),
            baseSurfaceConfig: { runtime.makeTmuxBaseSurfaceConfig() },
            paneViewTheme: { .remuxDark },
            createPaneSurface: { _, _, _, _, _, _, _, _ in
                XCTFail("topology alone must not create a pane renderer")
            }
        )
    }

    private func snapshot(
        phase: TmuxSessionController.PaneInfo.Phase
    ) -> TmuxSessionController.TopologySnapshot {
        .init(
            sessionName: "session",
            windows: [window(activePaneID: 10)],
            panes: [pane(id: 10, phase: phase)],
            activeWindowID: 1
        )
    }

    private func twoPaneSnapshot(
        activePaneID: TmuxPaneID,
        zoomed: Bool = true
    ) -> TmuxSessionController.TopologySnapshot {
        .init(
            sessionName: "session",
            windows: [window(activePaneID: activePaneID, zoomed: zoomed)],
            panes: [pane(id: 10, phase: .live), pane(id: 11, phase: .live)],
            activeWindowID: 1
        )
    }

    private func crossWindowSnapshot(
        activeWindowID: TmuxWindowID,
        targetActivePaneID: TmuxPaneID
    ) -> TmuxSessionController.TopologySnapshot {
        .init(
            sessionName: "session",
            windows: [
                window(id: 1, active: activeWindowID == 1, activePaneID: 10),
                window(
                    id: 2,
                    active: activeWindowID == 2,
                    activePaneID: targetActivePaneID,
                    zoomed: false
                ),
            ],
            panes: [
                pane(id: 10, windowID: 1, phase: .live),
                pane(id: 20, windowID: 2, phase: .live),
                pane(id: 21, windowID: 2, phase: .live),
            ],
            activeWindowID: activeWindowID
        )
    }

    private func emptySnapshot() -> TmuxSessionController.TopologySnapshot {
        .init(sessionName: "session", windows: [], panes: [], activeWindowID: nil)
    }

    private func window(
        id: TmuxWindowID = 1,
        active: Bool = true,
        activePaneID: TmuxPaneID,
        zoomed: Bool = true
    ) -> TmuxSessionController.WindowInfo {
        .init(
            id: id,
            name: "",
            active: active,
            zoomed: zoomed,
            width: 80,
            height: 24,
            activePaneID: activePaneID
        )
    }

    private func pane(
        id: TmuxPaneID,
        windowID: TmuxWindowID = 1,
        phase: TmuxSessionController.PaneInfo.Phase
    ) -> TmuxSessionController.PaneInfo {
        .init(
            id: id,
            windowID: windowID,
            x: 0,
            y: 0,
            width: 80,
            height: 24,
            currentCommand: "",
            currentPath: "",
            phase: phase
        )
    }
}
