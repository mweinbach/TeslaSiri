import AppKit
import QuartzCore
import SwiftUI

/// The caller establishes layer backing during setup and supplies the ancestor
/// whose layout contains this active constraint. Geometry has one owner.
@MainActor
func animateConstraint(
    _ constraint: NSLayoutConstraint,
    to value: CGFloat,
    in container: NSView,
    animated: Bool
) {
    container.layoutSubtreeIfNeeded()
    guard animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
        constraint.constant = value
        container.layoutSubtreeIfNeeded()
        return
    }
    NSAnimationContext.runAnimationGroup { context in
        context.duration = 0.24
        context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        context.allowsImplicitAnimation = true
        constraint.constant = value
        container.layoutSubtreeIfNeeded()
    }
}

/// Caller owns this coordinator for the view's lifetime and owns focus/input policy.
@available(macOS 14.0, *)
@MainActor
final class FadeCoordinator {
    private weak var view: NSView?
    private var revision = 0

    init(view: NSView) { self.view = view }

    func setVisible(_ visible: Bool, animated: Bool) {
        revision += 1
        let request = revision
        guard let view else { return }

        let shouldAnimate = animated
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if visible { view.isHidden = false }
        guard shouldAnimate else {
            view.alphaValue = visible ? 1 : 0
            view.isHidden = !visible
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            view.animator().alphaValue = visible ? 1 : 0
        } completionHandler: { [weak self] in
            // NSAnimationContext documents main-thread completion, including
            // cancellation. The revision guards semantic cleanup after reversal.
            MainActor.assumeIsolated {
                guard let self, self.revision == request else { return }
                self.view?.isHidden = !visible
            }
        }
    }

    func invalidate() {
        revision += 1
        view = nil
    }
}

/// Only for an app-owned layer whose position is not also driven by view layout.
/// Provides position continuity; a new basic curve does not preserve velocity.
@MainActor
func retargetPosition(of layer: CALayer, to target: CGPoint, animated: Bool) {
    let key = "example.position"
    let visiblePosition = layer.presentation()?.position ?? layer.position
    let shouldAnimate = animated
        && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

    CATransaction.begin()
    CATransaction.setDisableActions(true)
    layer.position = target
    if shouldAnimate {
        let animation = CABasicAnimation(keyPath: "position")
        animation.fromValue = NSValue(point: visiblePosition)
        animation.toValue = NSValue(point: target)
        animation.duration = 0.25
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(animation, forKey: key)
    } else {
        layer.removeAnimation(forKey: key)
    }
    CATransaction.commit()
}

/// Dedicated app-owned clock only. Supports unit-speed pause/resume, not arbitrary
/// clock configurations. Pauses descendant animations as well.
@MainActor
func pauseDedicatedLayer(_ layer: CALayer) {
    guard layer.speed == 1 else { return }
    let localTime = layer.convertTime(CACurrentMediaTime(), from: nil)
    layer.speed = 0
    layer.timeOffset = localTime
}

@MainActor
func resumeDedicatedLayer(_ layer: CALayer) {
    guard layer.speed == 0 else { return }
    let pausedTime = layer.timeOffset
    layer.speed = 1
    layer.timeOffset = 0
    layer.beginTime = 0
    layer.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil) - pausedTime
}

@available(macOS 15.0, *)
@MainActor
struct NativeEmphasisView: NSViewRepresentable {
    var emphasized: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        view.alphaValue = emphasized ? 1 : 0.35
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let destination: CGFloat = emphasized ? 1 : 0.35
        guard nsView.alphaValue != destination else { return }
        if reduceMotion {
            nsView.alphaValue = destination
        } else {
            context.animate {
                nsView.alphaValue = destination
            }
        }
    }
}
