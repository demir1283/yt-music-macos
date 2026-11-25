import SwiftUI
import AppKit

/// Two-finger swipes left and right over a view, one step per swipe (+1: the next, -1: the
/// one before), and a mouse's sideways wheel, one step per tick at most every 0.3 s.
/// Scrolling up and down passes through untouched, so the page around still scrolls; a
/// sideways swipe, momentum included, goes to the view alone.
private struct HorizontalSwipe: ViewModifier {
    let step: (Int) -> Void
    @ViewState var tracker = SwipeTracker()

    func body(content: Content) -> some View {
        tracker.action = step
        return content
            // Plain hover: the swipe itself must not end it (scroll-aware hover would).
            .onHover { inside in inside ? tracker.start() : tracker.stop() }
            .onDisappear { tracker.stop() }
    }
}

/// Watches the window's scroll events while the pointer is over the view.
final class SwipeTracker {
    var action: ((Int) -> Void)?
    private var monitor: Any?
    private var dx: CGFloat = 0
    private var dy: CGFloat = 0
    /// Decided by the first few points of a gesture: sideways (ours) or not.
    private var sideways: Bool?
    private var fired = false
    private var lastTick: TimeInterval = 0
    /// How far the fingers travel before a swipe counts.
    private static let threshold: CGFloat = 40

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.handle(event) ?? event
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        sideways = nil
    }

    deinit { if let monitor { NSEvent.removeMonitor(monitor) } }

    /// nil: the event is used up here.
    private func handle(_ e: NSEvent) -> NSEvent? {
        // The glide after lifting the fingers belongs to the gesture before it.
        if !e.momentumPhase.isEmpty { return sideways == true ? nil : e }

        // A mouse wheel (no gesture phases).
        if e.phase.isEmpty {
            guard e.scrollingDeltaX != 0, abs(e.scrollingDeltaX) > abs(e.scrollingDeltaY) else { return e }
            let now = ProcessInfo.processInfo.systemUptime
            if now - lastTick > 0.3 {
                lastTick = now
                action?(e.scrollingDeltaX < 0 ? 1 : -1)
            }
            return nil
        }

        if e.phase.contains(.began) || e.phase.contains(.mayBegin) {
            dx = 0; dy = 0; sideways = nil; fired = false
        }
        dx += e.scrollingDeltaX
        dy += e.scrollingDeltaY
        if sideways == nil, abs(dx) + abs(dy) > 6 { sideways = abs(dx) > abs(dy) }
        guard sideways == true else { return e }
        // The content follows the fingers: moving left (negative) brings the next one.
        if !fired, abs(dx) > Self.threshold {
            fired = true
            action?(dx < 0 ? 1 : -1)
        }
        return nil
    }
}

extension View {
    func onHorizontalSwipe(_ step: @escaping (Int) -> Void) -> some View {
        modifier(HorizontalSwipe(step: step))
    }
}
