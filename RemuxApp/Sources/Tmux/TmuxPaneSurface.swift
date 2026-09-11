import Foundation
import GhosttyKit
import QuartzCore
import UIKit

/// MainActor owner of one retained canonical pane terminal and its current
/// renderer surface. Normal pane switches retain this entire object unchanged;
/// only renderer failure replaces the renderer over the same terminal and
/// UIView. Settings update the live surface in place.
@MainActor
final class TmuxPaneSurface {
    let paneID: TmuxPaneID
    let instanceID = TerminalSurfaceInstanceID()
    let view: GhosttyKitSurfaceView

    private let app: ghostty_app_t
    private let controller: TmuxSessionController
    private let terminal: TmuxSessionController.RetainedPaneTerminal
    private let callbackBox: CallbackBox
    private let failureRelay: FailureRelay
    private let onRendererFailure: (TmuxPaneID) -> Void

    private struct Renderer {
        let handle: ghostty_terminal_surface_t
        let control: GhosttyKitControlSurface
    }

    private enum Lifecycle {
        case active
        case replacing
        case closing
        case closed
    }

    private var renderer: Renderer?
    private(set) var managedSurface: GhosttyManagedSurface?
    private var presented = false
    private var focused = false
    private var sceneActive = true
    private var lifecycle = Lifecycle.active
    private var rendererFailureReported = false
    #if DEBUG
    var suppressReplacementPublicationForTesting = false
    #endif
    private var rendererIsAvailable = true
    private var hasPublishedFrame = false
    private var presentationFailure: TerminalDisconnectReason?
    private var firstFrameObservation: NSKeyValueObservation?
    private var firstFrameDeadline: Task<Void, Never>?
    var onPresentationChange: (() -> Void)?

    var presentation: TerminalPanePresentation {
        if let presentationFailure { return .failed(presentationFailure) }
        guard !isClosing, rendererIsAvailable, renderer != nil,
              view.window != nil, hasPublishedFrame else { return .pending }
        return .ready
    }

    private func observeFirstFrame() {
        firstFrameObservation = nil
        hasPublishedFrame = false
        guard let layer = GhosttyIOSurfaceFrame.rendererLayer(in: view.layer) else { return }
        let reference = LayerReference(layer)
        let relay = previewRelay
        firstFrameObservation = layer.observe(\.contents, options: [.initial, .new]) { _, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let pane = relay.pane, let layer = reference.layer,
                          GhosttyIOSurfaceFrame.rendererLayer(in: pane.view.layer) === layer
                    else { return }
                    pane.recordFirstFrameIfPublished(on: layer)
                }
            }
        }
    }

    private func recordFirstFrameIfPublished(on layer: CALayer) {
        guard !hasPublishedFrame, presented, sceneActive,
              let dimensions = GhosttyIOSurfaceFrame.dimensions(in: layer),
              dimensions.width == Int(canonicalViewportMetrics.pixelWidth),
              dimensions.height == Int(canonicalViewportMetrics.pixelHeight)
        else { return }
        hasPublishedFrame = true
        GhosttyRuntimeTrace.diagnostics(
            "tmuxPane.firstFrame pane=\(paneID) attached=\(view.window != nil) size=\(dimensions.width)x\(dimensions.height)"
        )
        firstFrameObservation = nil
        updatePresentationReadiness()
    }

    private func updatePresentationReadiness() {
        // A detached/hidden view does not consume the local frame deadline.
        // Hydration and network startup are owned by the session/controller.
        let awaitingFrame = lifecycle == .active && rendererIsAvailable
            && presented && sceneActive && view.window != nil
            && !hasPublishedFrame && presentationFailure == nil
        if !awaitingFrame {
            firstFrameDeadline?.cancel()
            firstFrameDeadline = nil
        } else if firstFrameDeadline == nil {
            firstFrameDeadline = Task { @MainActor [weak self] in
                try? await Task.sleep(for: Self.framePublicationTimeout)
                guard !Task.isCancelled, let self else { return }
                self.firstFrameDeadline = nil
                GhosttyRuntimeTrace.diagnostics("tmuxPane.firstFrameTimeout pane=\(self.paneID)")
                self.presentationFailure = TerminalDisconnectReason(
                    kind: .runtime,
                    message: "Terminal did not publish its first frame. Reconnect to try again."
                )
                self.rendererIsAvailable = false
                self.managedSurface?.beginRendererRecovery(snapshot: self.currentRendererSnapshot())
                self.onPresentationChange?()
            }
        }
        onPresentationChange?()
    }
    private var closeCompletions: [@MainActor @Sendable () -> Void] = []
    private var framePublicationWait: FramePublicationWait?
    private var presentationTask: Task<Void, Never>?
    private var presentationGeneration: UInt64 = 0
    private let previewRelay = PreviewRelay()
    private var canonicalViewportMetrics: GhosttySurfaceDisplayMetrics
    private var appliedDisplayMetrics: GhosttySurfaceDisplayMetrics

    enum CreateError: Error {
        case surfaceCreationFailed(ghostty_terminal_surface_result_e)
        case registrationFailed(TmuxSessionController.SurfaceRegistrationError)
    }

    enum RendererReplacementResult: Equatable {
        case replaced
        case busy
        case failed
    }

    private final class FailureRelay {
        weak var pane: TmuxPaneSurface?
    }

    private enum FramePublication {
        case ready
        case captured(GhosttyIOSurfaceFrame)
    }

    private enum FramePublicationRequest {
        case presentation(
            expectedWidth: UInt32,
            expectedHeight: UInt32,
            keepVisibleAfterSuccess: Bool
        )
        case preview(GhosttyPanePreviewSession.PixelBudget)
    }

    private final class FramePublicationWait: @unchecked Sendable {
        let request: FramePublicationRequest
        var observation: NSKeyValueObservation?
        var continuation: CheckedContinuation<FramePublication?, Never>?
        var timeoutTask: Task<Void, Never>?

        init(request: FramePublicationRequest) {
            self.request = request
        }

        var isPreview: Bool {
            if case .preview = request { return true }
            return false
        }
    }

    private final class PreviewRelay: @unchecked Sendable {
        weak var pane: TmuxPaneSurface?
    }

    private static let framePublicationTimeout: Duration = .seconds(2)

    private final class LayerReference: @unchecked Sendable {
        weak var layer: CALayer?

        init(_ layer: CALayer) {
            self.layer = layer
        }
    }

    private final class CallbackBox: @unchecked Sendable {
        enum TrackedWriteTransport {
            case exact
            case literal
        }

        private struct TrackedWrite {
            let transport: TrackedWriteTransport
            let completion: @Sendable (Bool) -> Void
        }

        let controller: TmuxSessionController
        let paneID: TmuxPaneID
        let failureRelay: FailureRelay
        private var trackedWrite: TrackedWrite?

        init(
            controller: TmuxSessionController,
            paneID: TmuxPaneID,
            failureRelay: FailureRelay
        ) {
            self.controller = controller
            self.paneID = paneID
            self.failureRelay = failureRelay
        }

        static let writeCallback: ghostty_terminal_surface_write_cb = { userdata, pointer, count in
            // ghostty.h: write_cb fires only from terminal-surface input
            // operations on the presentation-owner thread, never from the
            // output feed. `trackedWrite` is single-threaded because of
            // this contract.
            assert(Thread.isMainThread)
            guard let userdata else { return false }
            let box = Unmanaged<CallbackBox>.fromOpaque(userdata).takeUnretainedValue()
            guard count > 0 else { return true }
            guard let pointer else { return false }
            if let trackedWrite = box.trackedWrite {
                box.trackedWrite = nil
                let bytes = Data(bytes: pointer, count: count)
                let admitted = switch trackedWrite.transport {
                case .exact:
                    box.controller.sendTrackedInput(
                        paneID: box.paneID,
                        bytes,
                        completion: trackedWrite.completion
                    )
                case .literal:
                    box.controller.sendTrackedLiteralInput(
                        paneID: box.paneID,
                        bytes,
                        completion: trackedWrite.completion
                    )
                }
                if !admitted {
                    trackedWrite.completion(false)
                }
                return admitted
            }
            return box.controller.sendInput(
                paneID: box.paneID,
                Data(bytes: pointer, count: count)
            )
        }

        func performTrackedWrite(
            transport: TrackedWriteTransport,
            completion: @escaping @Sendable (Bool) -> Void,
            _ operation: () -> Bool
        ) {
            MainActor.preconditionIsolated()
            precondition(trackedWrite == nil)
            trackedWrite = TrackedWrite(transport: transport, completion: completion)
            _ = operation()
            guard trackedWrite != nil else { return }
            trackedWrite = nil
            completion(false)
        }

        static let healthCallback: ghostty_terminal_surface_renderer_health_cb = { userdata, health in
            guard health == GHOSTTY_RENDERER_HEALTH_UNHEALTHY, let userdata else { return }
            let box = Unmanaged<CallbackBox>.fromOpaque(userdata).takeUnretainedValue()
            DispatchQueue.main.async { [weak relay = box.failureRelay] in
                MainActor.assumeIsolated { relay?.pane?.rendererDidFail() }
            }
        }
    }

    static func create(
        app: ghostty_app_t,
        controller: TmuxSessionController,
        terminal: TmuxSessionController.RetainedPaneTerminal,
        baseConfig: ghostty_terminal_surface_config_s,
        metrics: GhosttySurfaceDisplayMetrics,
        theme: TerminalTheme,
        onRendererFailure: @escaping @MainActor (TmuxPaneID) -> Void,
        completion: @escaping @MainActor (Result<TmuxPaneSurface, CreateError>) -> Void
    ) {
        let relay = FailureRelay()
        let callbackBox = CallbackBox(
            controller: controller,
            paneID: terminal.paneID,
            failureRelay: relay
        )
        let view = GhosttyKitSurfaceView(frame: CGRect(
            x: 0,
            y: 0,
            width: Double(metrics.pixelWidth) / metrics.contentScale,
            height: Double(metrics.pixelHeight) / metrics.contentScale
        ))
        view.contentScaleFactor = metrics.contentScale
        view.applyTerminalTheme(theme)

        var config = configured(
            baseConfig,
            view: view,
            metrics: metrics,
            callbackBox: callbackBox,
            visible: false,
            focused: false
        )
        var nativeSurface: ghostty_terminal_surface_t?
        let result = ghostty_terminal_surface_new(
            app,
            terminal.handle,
            &config,
            &nativeSurface
        )
        guard result == GHOSTTY_TERMINAL_SURFACE_RESULT_OK, let nativeSurface else {
            completion(.failure(.surfaceCreationFailed(result)))
            return
        }
        view.alignGhosttyRendererSublayers()

        let pane = TmuxPaneSurface(
            app: app,
            controller: controller,
            terminal: terminal,
            view: view,
            surface: nativeSurface,
            metrics: metrics,
            callbackBox: callbackBox,
            failureRelay: relay,
            onRendererFailure: onRendererFailure
        )
        relay.pane = pane
        controller.registerTerminalSurface(
            paneID: terminal.paneID,
            surface: nativeSurface
        ) { result in
            switch result {
            case .success:
                completion(.success(pane))
            case .failure(let error):
                pane.destroyUnregisteredRenderer()
                completion(.failure(.registrationFailed(error)))
            }
        }
    }

    private init(
        app: ghostty_app_t,
        controller: TmuxSessionController,
        terminal: TmuxSessionController.RetainedPaneTerminal,
        view: GhosttyKitSurfaceView,
        surface: ghostty_terminal_surface_t,
        metrics: GhosttySurfaceDisplayMetrics,
        callbackBox: CallbackBox,
        failureRelay: FailureRelay,
        onRendererFailure: @escaping (TmuxPaneID) -> Void
    ) {
        self.app = app
        self.controller = controller
        self.terminal = terminal
        paneID = terminal.paneID
        self.view = view
        self.callbackBox = callbackBox
        self.failureRelay = failureRelay
        self.onRendererFailure = onRendererFailure
        canonicalViewportMetrics = metrics
        appliedDisplayMetrics = metrics
        let control = GhosttyKitControlSurface(
            surface: surface,
            scaleFactor: metrics.contentScale,
            onFailure: { [failureRelay] _ in
                failureRelay.pane?.rendererDidFail()
            }
        )
        renderer = Renderer(handle: surface, control: control)
        previewRelay.pane = self
        view.onWindowAttachmentChange = { [weak self] in
            // UIKit can attach during a SwiftUI update. Publish after that
            // transaction while deriving attachment from the current view.
            DispatchQueue.main.async { [weak self] in self?.updatePresentationReadiness() }
        }
        observeFirstFrame()
    }

    var rawSurface: ghostty_terminal_surface_t? { renderer?.handle }

    func sendPasteAwaitingCommandCompletion(_ text: String) async -> Bool {
        guard !text.isEmpty, lifecycle == .active, let renderer else { return false }
        return await performInputAwaitingCommandCompletion(transport: .literal) {
            renderer.control.sendPaste(text)
        }
    }

    func sendKeyEventAwaitingCommandCompletion(
        _ event: GhosttySurfaceKeyEvent
    ) async -> Bool {
        guard lifecycle == .active, let renderer else { return false }
        return await performInputAwaitingCommandCompletion(transport: .exact) {
            renderer.control.sendKeyEvent(event)
        }
    }

    private func performInputAwaitingCommandCompletion(
        transport: CallbackBox.TrackedWriteTransport,
        _ operation: () -> Bool
    ) async -> Bool {
        await withCheckedContinuation { continuation in
            callbackBox.performTrackedWrite(
                transport: transport,
                completion: { continuation.resume(returning: $0) },
                operation
            )
        }
    }

    func screenSurface(id: UUID) -> GhosttyManagedSurface {
        if let managedSurface {
            precondition(
                managedSurface.id == id,
                "managed surface identity must remain stable for one tmux pane"
            )
            if renderer != nil { managedSurface.refreshInteractionState() }
            return managedSurface
        }
        guard let renderer else {
            preconditionFailure("first screen surface requires a registered renderer")
        }

        let managed = GhosttyManagedSurface(
            id: id,
            view: view,
            controlSurface: renderer.control,
            paneOwner: self,
            interactionState: renderer.control.interactionState()
        )
        managedSurface = managed
        applyPresentationActivity()
        return managed
    }

    func setPresented(_ presented: Bool) {
        guard lifecycle != .closed, lifecycle != .closing else { return }
        guard self.presented != presented else { return }
        self.presented = presented
        applyPresentationActivity()
    }

    func setFocused(_ focused: Bool) {
        guard lifecycle != .closed, lifecycle != .closing else { return }
        guard self.focused != focused else { return }
        self.focused = focused
        applyPresentationActivity()
    }

    func setSceneActive(_ active: Bool) {
        guard lifecycle != .closed, lifecycle != .closing else { return }
        guard active != sceneActive else { return }
        sceneActive = active
        applyPresentationActivity()
    }

    func refreshInteractionState() {
        managedSurface?.refreshInteractionState()
    }

    func updateCanonicalViewportMetrics(_ metrics: GhosttySurfaceDisplayMetrics) {
        canonicalViewportMetrics = metrics
    }

    @discardableResult
    func updateDisplay(metrics: GhosttySurfaceDisplayMetrics) -> Bool {
        canonicalViewportMetrics = metrics
        return applyDisplayMetrics(metrics)
    }

    func cancelPresentationPreparation() {
        presentationGeneration &+= 1
        let hadTask = presentationTask != nil
        let hadWait = framePublicationWait != nil
        presentationTask?.cancel()
        presentationTask = nil
        if hadWait {
            // The wait owns its transient visibility and hides exactly once.
            cancelFramePublicationWait()
        } else if hadTask, !presented {
            // Publication may have completed with keep-visible immediately
            // before the MainActor task is cancelled.
            _ = renderer?.control.setVisible(false)
        }
    }

    @discardableResult
    func applyTerminalConfiguration(theme: TerminalTheme) -> Bool {
        guard lifecycle == .active, let renderer else { return false }
        let result = ghostty_terminal_surface_update_config(renderer.handle)
        guard result == GHOSTTY_TERMINAL_SURFACE_RESULT_OK else {
            NSLog(
                "tmuxPane.configUpdate failed pane=\(paneID) result=\(String(describing: result))"
            )
            return false
        }
        view.applyTerminalTheme(theme)
        managedSurface?.notifyLocalSelectionGeometryChanged()
        return true
    }

    func replaceRenderer(
        baseConfig: ghostty_terminal_surface_config_s,
        metrics: GhosttySurfaceDisplayMetrics,
        theme: TerminalTheme,
        completion: @escaping @MainActor (RendererReplacementResult) -> Void
    ) {
        guard lifecycle == .active, presentationTask == nil else {
            completion(lifecycle == .replacing || presentationTask != nil ? .busy : .failed)
            return
        }
        lifecycle = .replacing
        rendererIsAvailable = false
        hasPublishedFrame = false
        firstFrameObservation = nil
        updatePresentationReadiness()
        // This call is the single replacement attempt for the triggering
        // failure/settings change. Failures inside it return through
        // completion; they must not recursively schedule another attempt.
        rendererFailureReported = true
        cancelPresentationPreparation()
        if managedSurface?.rendererIsAvailable == true {
            managedSurface?.beginRendererRecovery(snapshot: currentRendererSnapshot())
        }

        let installReplacement = { [self] in
            guard lifecycle == .replacing else {
                finishCloseIfRendererless()
                completion(.failed)
                return
            }
            view.applyTerminalTheme(theme)
            view.frame.size = CGSize(
                width: Double(metrics.pixelWidth) / metrics.contentScale,
                height: Double(metrics.pixelHeight) / metrics.contentScale
            )
            view.contentScaleFactor = metrics.contentScale
            canonicalViewportMetrics = metrics
            appliedDisplayMetrics = metrics

            var config = Self.configured(
                baseConfig,
                view: view,
                metrics: metrics,
                callbackBox: callbackBox,
                visible: false,
                focused: false
            )
            var replacement: ghostty_terminal_surface_t?
            let result = ghostty_terminal_surface_new(
                app,
                terminal.handle,
                &config,
                &replacement
            )
            guard result == GHOSTTY_TERMINAL_SURFACE_RESULT_OK, let replacement else {
                lifecycle = .active
                managedSurface?.finishRendererReplacement(isAvailable: false)
                completion(.failed)
                return
            }
            view.alignGhosttyRendererSublayers()

            let wrapper = GhosttyKitControlSurface(
                surface: replacement,
                scaleFactor: metrics.contentScale,
                onFailure: { [failureRelay] _ in
                    failureRelay.pane?.rendererDidFail()
                }
            )
            renderer = Renderer(handle: replacement, control: wrapper)
            controller.registerTerminalSurface(paneID: paneID, surface: replacement) { [self] result in
                guard case .success = result else {
                    wrapper.invalidate()
                    ghostty_terminal_surface_free(replacement)
                    renderer = nil
                    if lifecycle == .closing {
                        finishCloseIfRendererless()
                    } else {
                        lifecycle = .active
                    }
                    managedSurface?.finishRendererReplacement(isAvailable: false)
                    completion(.failed)
                    return
                }

                guard lifecycle != .closing else {
                    controller.unregisterTerminalSurface(
                        paneID: paneID,
                        surface: replacement
                    ) { [self] in
                        wrapper.invalidate()
                        ghostty_terminal_surface_free(replacement)
                        renderer = nil
                        finishCloseIfRendererless()
                        completion(.failed)
                    }
                    return
                }
                lifecycle = .active
                observeFirstFrame()
                managedSurface?.replaceControlSurface(wrapper)
                guard let rendererLayer = GhosttyIOSurfaceFrame.rendererLayer(in: view.layer) else {
                    managedSurface?.finishRendererReplacement(isAvailable: false)
                    completion(.failed)
                    return
                }

                presentationGeneration &+= 1
                let generation = presentationGeneration
                presentationTask = Task { @MainActor [weak self] in
                    guard let self else {
                        completion(.failed)
                        return
                    }
                    let publication = await matchingPublication(
                        on: rendererLayer,
                        request: .presentation(
                            expectedWidth: metrics.pixelWidth,
                            expectedHeight: metrics.pixelHeight,
                            keepVisibleAfterSuccess: presented && sceneActive
                        )
                    )
                    guard presentationGeneration == generation else {
                        completion(.failed)
                        return
                    }
                    presentationTask = nil
                    let didPublishFrame = publication != nil
                    if !didPublishFrame {
                        GhosttyRuntimeTrace.diagnostics(
                            "tmuxPane.rendererReplacement firstFrameTimeout pane=\(paneID)"
                        )
                    }
                    rendererIsAvailable = didPublishFrame
                    hasPublishedFrame = didPublishFrame
                    // A failed attempt must not recursively replace itself.
                    rendererFailureReported = !didPublishFrame
                    managedSurface?.finishRendererReplacement(isAvailable: didPublishFrame)
                    applyPresentationActivity()
                    completion(didPublishFrame ? .replaced : .failed)
                }
            }
        }

        guard let oldRenderer = renderer else {
            installReplacement()
            return
        }
        controller.unregisterTerminalSurface(
            paneID: paneID,
            surface: oldRenderer.handle
        ) { [self] in
            oldRenderer.control.invalidate()
            ghostty_terminal_surface_free(oldRenderer.handle)
            if renderer?.handle == oldRenderer.handle { renderer = nil }
            guard lifecycle != .closing else {
                finishCloseIfRendererless()
                completion(.failed)
                return
            }
            installReplacement()
        }
    }

    var isClosing: Bool { lifecycle == .closing || lifecycle == .closed }

    func close(completion: @escaping @MainActor @Sendable () -> Void = {}) {
        if lifecycle == .closed {
            completion()
            return
        }
        closeCompletions.append(completion)
        guard lifecycle != .closing else { return }
        let wasReplacing = lifecycle == .replacing
        lifecycle = .closing
        firstFrameObservation = nil
        updatePresentationReadiness()
        view.onWindowAttachmentChange = nil
        onPresentationChange = nil
        cancelPresentationPreparation()
        previewRelay.pane = nil
        failureRelay.pane = nil
        managedSurface?.prepareForPermanentRemoval()
        guard !wasReplacing else { return }
        guard let renderer else {
            finishCloseIfRendererless()
            return
        }
        controller.unregisterTerminalSurface(
            paneID: paneID,
            surface: renderer.handle
        ) { [self] in
            renderer.control.invalidate()
            ghostty_terminal_surface_free(renderer.handle)
            if self.renderer?.handle == renderer.handle { self.renderer = nil }
            finishCloseIfRendererless()
        }
    }

    /// Cancel a pending picker frame before pane selection owns the surface.
    /// Invalidating the observation prevents a delayed preview completion
    /// from racing the pane's presentation.
    func cancelPickerCaptureForPresentation() {
        guard framePublicationWait?.isPreview == true else { return }
        cancelFramePublicationWait()
    }

    func capturePickerPreview(
        columns: UInt32,
        rows: UInt32,
        budget: GhosttyPanePreviewSession.PixelBudget
    ) async -> CGImage? {
        guard lifecycle == .active,
              framePublicationWait == nil,
              presentationTask == nil,
              columns > 0, rows > 0,
              let renderer,
              let rendererLayer = GhosttyIOSurfaceFrame.rendererLayer(in: view.layer)
        else { return nil }
        let current = renderer.control.currentSize()

        guard (current.columns == columns && current.rows == rows)
                || isViewportSized(current)
        else { return nil }

        let frame: GhosttyIOSurfaceFrame
        if presented {
            guard let dimensions = GhosttyIOSurfaceFrame.dimensions(in: rendererLayer),
                  let sourceRect = previewSourceRect(
                    width: dimensions.width,
                    height: dimensions.height,
                    budget: budget
                  )
            else { return nil }
            guard let published = try? GhosttyIOSurfaceFrame.read(
                from: rendererLayer,
                sourceRect: sourceRect
            ) else { return nil }
            frame = published
        } else {
            guard let publication = await matchingPublication(
                on: rendererLayer,
                request: .preview(budget)
            ), case .captured(let published) = publication
            else { return nil }
            frame = published
        }

        guard let image = await makePreviewImage(
            from: frame,
            budget: budget
        ) else {
            return nil
        }
        return image
    }

    private func rendererDidFail() {
        guard lifecycle == .active, !rendererFailureReported else { return }
        rendererFailureReported = true
        rendererIsAvailable = false
        updatePresentationReadiness()
        managedSurface?.beginRendererRecovery(snapshot: currentRendererSnapshot())
        onRendererFailure(paneID)
    }

    private func currentRendererSnapshot() -> CGImage? {
        guard let layer = GhosttyIOSurfaceFrame.rendererLayer(in: view.layer),
              let frame = try? GhosttyIOSurfaceFrame.read(from: layer),
              let width = UInt32(exactly: frame.width),
              let height = UInt32(exactly: frame.height)
        else { return nil }
        return try? frame.image(maxWidth: width, maxHeight: height)
    }

    private func applyPresentationActivity() {
        let visible = presented && sceneActive
        let active = focused && visible
        if let managedSurface {
            managedSurface.setFocused(active)
            managedSurface.setVisible(visible)
        } else {
            _ = renderer?.control.setFocused(active)
            _ = renderer?.control.setVisible(visible)
        }
        if let layer = GhosttyIOSurfaceFrame.rendererLayer(in: view.layer) {
            recordFirstFrameIfPublished(on: layer)
        }
        updatePresentationReadiness()
    }

    private func destroyUnregisteredRenderer() {
        lifecycle = .closed
        firstFrameObservation = nil
        firstFrameDeadline?.cancel()
        view.onWindowAttachmentChange = nil
        cancelPresentationPreparation()
        previewRelay.pane = nil
        failureRelay.pane = nil
        renderer?.control.invalidate()
        if let renderer { ghostty_terminal_surface_free(renderer.handle) }
        renderer = nil
    }

    private func finishCloseIfRendererless() {
        guard lifecycle == .closing, renderer == nil else { return }
        lifecycle = .closed
        let completions = closeCompletions
        closeCompletions.removeAll()
        for completion in completions { completion() }
    }

    private static func configured(
        _ base: ghostty_terminal_surface_config_s,
        view: GhosttyKitSurfaceView,
        metrics: GhosttySurfaceDisplayMetrics,
        callbackBox: CallbackBox,
        visible: Bool,
        focused: Bool
    ) -> ghostty_terminal_surface_config_s {
        var config = base
        config.platform_tag = GHOSTTY_PLATFORM_IOS
        config.platform = ghostty_platform_u(ios: ghostty_platform_ios_s(
            uiview: Unmanaged.passUnretained(view).toOpaque()
        ))
        config.userdata = Unmanaged.passUnretained(callbackBox).toOpaque()
        config.renderer_health_cb = CallbackBox.healthCallback
        config.write_cb = CallbackBox.writeCallback
        config.scale_factor = metrics.contentScale
        config.width_px = metrics.pixelWidth
        config.height_px = metrics.pixelHeight
        config.visible = visible
        config.focused = focused
        return config
    }

    private func matchingPublication(
        on layer: CALayer,
        request: FramePublicationRequest
    ) async -> FramePublication? {
        // Drain stale display invalidation before observing the next renderer
        // publication.
        layer.displayIfNeeded()
        return await withCheckedContinuation { continuation in
            guard !Task.isCancelled, framePublicationWait == nil else {
                continuation.resume(returning: nil)
                return
            }
            let wait = FramePublicationWait(request: request)
            let layerReference = LayerReference(layer)
            let relay = previewRelay
            wait.continuation = continuation
            framePublicationWait = wait
            wait.timeoutTask = Task { @MainActor [weak self, weak wait] in
                try? await Task.sleep(for: Self.framePublicationTimeout)
                guard !Task.isCancelled, let self, let wait else { return }
                self.finishFramePublicationWait(wait, publication: nil)
            }
            wait.observation = layer.observe(\.contents, options: [.new]) { [weak wait] _, _ in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        guard let pane = relay.pane,
                              let wait,
                              let layer = layerReference.layer
                        else { return }
                        pane.finishFramePublicationIfMatching(wait, layer: layer)
                    }
                }
            }
            switch request {
            case .preview:
                guard renderer?.control.requestFrame() == true else {
                    finishFramePublicationWait(wait, publication: nil)
                    return
                }
            case .presentation(_, _, let keepVisibleAfterSuccess):
                _ = renderer?.control.setFocused(keepVisibleAfterSuccess)
                guard renderer?.control.setVisible(true) == true,
                      renderer?.control.requestFrame() == true else {
                    finishFramePublicationWait(wait, publication: nil)
                    return
                }
            }
        }
    }

    private func finishFramePublicationIfMatching(
        _ wait: FramePublicationWait,
        layer: CALayer
    ) {
        guard framePublicationWait === wait,
              let dimensions = GhosttyIOSurfaceFrame.dimensions(in: layer)
        else { return }

        switch wait.request {
        case .presentation(let expectedWidth, let expectedHeight, _):
            #if DEBUG
            guard !suppressReplacementPublicationForTesting else { return }
            #endif
            guard dimensions.width == Int(expectedWidth),
                  dimensions.height == Int(expectedHeight)
            else { return }
            finishFramePublicationWait(wait, publication: .ready)

        case .preview(let budget):
            guard let sourceRect = previewSourceRect(
                width: dimensions.width,
                height: dimensions.height,
                budget: budget
            ) else {
                finishFramePublicationWait(wait, publication: nil)
                return
            }
            let frame: GhosttyIOSurfaceFrame
            do {
                frame = try GhosttyIOSurfaceFrame.read(
                    from: layer,
                    sourceRect: sourceRect
                )
            } catch {
                GhosttyRuntimeTrace.diagnostics(
                    "tmuxPane.frameRead failed pane=\(paneID) error=\(String(describing: error))"
                )
                finishFramePublicationWait(wait, publication: nil)
                return
            }
            finishFramePublicationWait(wait, publication: .captured(frame))
        }
    }

    private func finishFramePublicationWait(
        _ wait: FramePublicationWait,
        publication: FramePublication?
    ) {
        guard framePublicationWait === wait else { return }
        wait.timeoutTask?.cancel()
        wait.timeoutTask = nil
        wait.observation?.invalidate()
        wait.observation = nil
        framePublicationWait = nil
        if case .presentation(_, _, let keepVisibleAfterSuccess) = wait.request,
           publication == nil || !keepVisibleAfterSuccess {
            if !presented { _ = renderer?.control.setVisible(false) }
        }
        let continuation = wait.continuation
        wait.continuation = nil
        continuation?.resume(returning: publication)
    }

    private func cancelFramePublicationWait() {
        guard let wait = framePublicationWait else { return }
        finishFramePublicationWait(wait, publication: nil)
    }

    private func makePreviewImage(
        from frame: GhosttyIOSurfaceFrame,
        budget: GhosttyPanePreviewSession.PixelBudget
    ) async -> CGImage? {
        let paneID = paneID
        return await Task.detached(priority: .userInitiated) {
            do {
                return try frame.image(
                    maxWidth: budget.width,
                    maxHeight: budget.height
                )
            } catch {
                GhosttyRuntimeTrace.diagnostics(
                    "tmuxPane.previewRead failed pane=\(paneID) error=\(String(describing: error))"
                )
                return nil
            }
        }.value
    }

    private func previewSourceRect(
        width: Int,
        height: Int,
        budget: GhosttyPanePreviewSession.PixelBudget
    ) -> CGRect? {
        let viewportAnchor = CGRect(x: 0, y: 0, width: width, height: height)
        let cropAnchor: CGRect
        if let cursor = renderer?.control.cursorGeometry() {
            let scale = CGFloat(canonicalViewportMetrics.contentScale)
            cropAnchor = CGRect(
                x: cursor.minX * scale,
                y: cursor.minY * scale,
                width: cursor.width * scale,
                height: cursor.height * scale
            )
        } else {
            cropAnchor = viewportAnchor
        }
        let cropWidth = UInt32(clamping: UInt64(budget.width) * 2)
        let cropHeight = UInt32(clamping: UInt64(budget.height) * 2)
        return GhosttyIOSurfaceFrame.sourceRect(
            width: width,
            height: height,
            centeredOn: cropAnchor,
            maxWidth: cropWidth,
            maxHeight: cropHeight
        ) ?? GhosttyIOSurfaceFrame.sourceRect(
            width: width,
            height: height,
            centeredOn: viewportAnchor,
            maxWidth: cropWidth,
            maxHeight: cropHeight
        )
    }

    private func isViewportSized(_ size: ghostty_surface_size_s) -> Bool {
        size.width_px == canonicalViewportMetrics.pixelWidth
            && size.height_px == canonicalViewportMetrics.pixelHeight
    }

    private func applyDisplayMetrics(
        _ metrics: GhosttySurfaceDisplayMetrics
    ) -> Bool {
        guard let renderer,
              metrics.contentScale == canonicalViewportMetrics.contentScale
        else { return false }
        if metrics == appliedDisplayMetrics { return true }
        view.frame.size = CGSize(
            width: Double(metrics.pixelWidth) / metrics.contentScale,
            height: Double(metrics.pixelHeight) / metrics.contentScale
        )
        view.contentScaleFactor = metrics.contentScale
        view.alignGhosttyRendererSublayers()
        guard renderer.control.updateDisplay(metrics: metrics) else {
            return false
        }
        appliedDisplayMetrics = metrics
        return true
    }

    deinit {
        let finalLifecycle = lifecycle
        assert(finalLifecycle == .closed, "TmuxPaneSurface deinit without close()")
    }
}
