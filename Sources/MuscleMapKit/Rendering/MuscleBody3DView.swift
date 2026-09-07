//
//  MuscleBody3DView.swift
//  Cinder
//
//  SwiftUI wrapper for the 3D muscle body. The scene shell (camera/lights)
//  appears immediately; the SDF mesh is built once per process on a background
//  queue (MuscleBodyGeometry.shared) and fades in when ready. Everything after
//  attach mutates in place — recoloring swaps the vertex-color source only.
//
//  Interaction: drag to spin the figure (with a flick's inertia), tap a muscle
//  region to select it. After a few idle seconds the body slowly auto-spins —
//  touching it takes control back.
//
//  Rendering is on demand: the SceneKit render loop only runs while something
//  is animating (fade-in, a flick, the tap pulse, the idle spin). A static body
//  — an inline card with autoRotate off — costs nothing between changes.
//

import SwiftUI
import SceneKit

public struct MuscleBody3DView: UIViewRepresentable {
    /// Per-muscle work intensity 0…1 (from set volume). Missing = untrained.
    var intensities: [MuscleGroup: Double]
    /// Muscles to render with the boosted "selected" tint.
    var selected: Set<MuscleGroup> = []
    /// Slow idle spin (paused while the user is dragging).
    var autoRotate = true
    /// Master switch for gestures — false for inline cards inside scroll views.
    var interactive = true
    /// Resting yaw (radians) — e.g. a 3/4 angle for static thumbnails.
    var initialYaw: Float = 0
    var onTapMuscle: ((MuscleGroup) -> Void)? = nil

    /// - Parameters:
    ///   - intensities: per-muscle work 0…1; muscles left out render untrained.
    ///   - selected: muscles drawn with the boosted highlight tint.
    ///   - autoRotate: slow idle spin, paused while the user is dragging.
    ///   - interactive: master switch for gestures — pass false inside a
    ///     scrolling list so the body doesn't fight the scroll.
    ///   - initialYaw: resting rotation in radians, e.g. a 3/4 angle.
    ///   - onTapMuscle: called with the muscle under a tap.
    public init(intensities: [MuscleGroup: Double],
                selected: Set<MuscleGroup> = [],
                autoRotate: Bool = true,
                interactive: Bool = true,
                initialYaw: Float = 0,
                onTapMuscle: ((MuscleGroup) -> Void)? = nil) {
        self.intensities = intensities
        self.selected = selected
        self.autoRotate = autoRotate
        self.interactive = interactive
        self.initialYaw = initialYaw
        self.onTapMuscle = onTapMuscle
    }

    public func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        let model = MuscleBodyModel()
        view.scene = model.scene
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 60
        view.allowsCameraControl = false
        view.isPlaying = false

        context.coordinator.attach(view: view, model: model)
        model.apply(intensities: intensities, selected: selected)
        context.coordinator.lastIntensities = intensities
        context.coordinator.lastSelected = selected
        context.coordinator.autoRotate = autoRotate

        if interactive {
            view.addGestureRecognizer(UIPanGestureRecognizer(
                target: context.coordinator, action: #selector(Coordinator.handlePan(_:))))
            view.addGestureRecognizer(UITapGestureRecognizer(
                target: context.coordinator, action: #selector(Coordinator.handleTap(_:))))
        }

        // Build (or fetch the cached) mesh off-main, then fade the figure in.
        let body = model.bodyNode
        let restingYaw = initialYaw
        body.opacity = 0
        Task.detached(priority: .userInitiated) {
            let mesh = MuscleBodyGeometry.shared()
            await MainActor.run { [weak coordinator = context.coordinator] in
                guard let coordinator, let model = coordinator.model else { return }
                model.attach(mesh: mesh)
                body.eulerAngles.y = restingYaw - 0.85
                coordinator.animate(for: 0.9)
                SCNTransaction.begin()
                SCNTransaction.animationDuration = 0.9
                SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeOut)
                body.opacity = 1
                body.eulerAngles.y = restingYaw
                SCNTransaction.commit()
                coordinator.scheduleIdleSpin(after: 1.2)
            }
        }
        return view
    }

    public func updateUIView(_ view: SCNView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onTapMuscle = onTapMuscle
        coordinator.autoRotate = autoRotate
        guard coordinator.lastIntensities != intensities
                || coordinator.lastSelected != selected else { return }
        coordinator.lastIntensities = intensities
        coordinator.lastSelected = selected
        coordinator.model?.apply(intensities: intensities, selected: selected)
    }

    public func makeCoordinator() -> Coordinator {
        let c = Coordinator()
        c.onTapMuscle = onTapMuscle
        return c
    }

    // MARK: - Coordinator

    public final class Coordinator: NSObject {
        weak var view: SCNView?
        var model: MuscleBodyModel?
        var onTapMuscle: ((MuscleGroup) -> Void)?
        var autoRotate = true
        var lastIntensities: [MuscleGroup: Double] = [:]
        var lastSelected: Set<MuscleGroup> = []
        private var idleTimer: Timer?
        private var pauseWork: DispatchWorkItem?

        func attach(view: SCNView, model: MuscleBodyModel) {
            self.view = view
            self.model = model
        }

        deinit {
            idleTimer?.invalidate()
            pauseWork?.cancel()
        }

        // MARK: On-demand render loop

        /// Run the render loop for `duration`, then pause it again unless the
        /// idle spin is running. Direct scene mutations (a drag, a recolor)
        /// redraw on their own; only actions and implicit animations need the
        /// loop ticking.
        func animate(for duration: TimeInterval) {
            view?.isPlaying = true
            pauseWork?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.pauseIfIdle() }
            pauseWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.05, execute: work)
        }

        private func pauseIfIdle() {
            guard model?.bodyNode.action(forKey: "idleSpin") == nil else { return }
            view?.isPlaying = false
        }

        // MARK: Drag to rotate (yaw free, pitch gently clamped)

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let body = model?.bodyNode else { return }
            switch gesture.state {
            case .began:
                stopIdleSpin()
            case .changed:
                // Yaw only — no tilt.
                let delta = gesture.translation(in: gesture.view)
                gesture.setTranslation(.zero, in: gesture.view)
                body.eulerAngles.y += Float(delta.x) * 0.011
            case .ended, .cancelled:
                let vx = gesture.velocity(in: gesture.view).x
                let spin = SCNAction.rotateBy(x: 0, y: CGFloat(vx) * 0.0006, z: 0,
                                              duration: 0.8)
                spin.timingMode = .easeOut
                animate(for: 0.8)
                body.runAction(spin)
                scheduleIdleSpin(after: 3.0)
            default:
                break
            }
        }

        // MARK: Tap to select a muscle region

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let view, let model else { return }
            let point = gesture.location(in: view)
            let hits = view.hitTest(point, options: [.boundingBoxOnly: false])
            guard let muscle = hits.lazy
                .compactMap({ model.muscle(atFace: $0.faceIndex) })
                .first else { return }

            // Feedback pulse — the recolor itself is the selection highlight.
            let up = SCNAction.scale(by: 1.025, duration: 0.10)
            up.timingMode = .easeOut
            let down = SCNAction.scale(by: 1 / 1.025, duration: 0.26)
            down.timingMode = .easeOut
            animate(for: 0.36)
            model.bodyNode.runAction(.sequence([up, down]))

            onTapMuscle?(muscle)
        }

        // MARK: Idle auto-spin

        func scheduleIdleSpin(after delay: TimeInterval) {
            guard autoRotate else { return }
            idleTimer?.invalidate()
            idleTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                self?.startIdleSpin()
            }
        }

        private func startIdleSpin() {
            guard autoRotate, let body = model?.bodyNode,
                  body.action(forKey: "idleSpin") == nil else { return }
            let spin = SCNAction.rotateBy(x: 0, y: 2 * .pi, z: 0, duration: 26)
            pauseWork?.cancel()
            view?.isPlaying = true
            body.runAction(.repeatForever(spin), forKey: "idleSpin")
        }

        private func stopIdleSpin() {
            idleTimer?.invalidate()
            model?.bodyNode.removeAction(forKey: "idleSpin")
            pauseIfIdle()
        }
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        MuscleBody3DView(
            intensities: [.chest: 1.0, .triceps: 0.6, .frontDelts: 0.5, .abs: 0.25]
        )
    }
}
