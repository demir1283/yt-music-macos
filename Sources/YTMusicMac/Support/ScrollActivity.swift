import SwiftUI
import AppKit
import QuartzCore

/// Whether the user is scrolling right now (a scroll-wheel or trackpad gesture, momentum
/// included). Only a timestamp is kept per scroll event: nothing redraws because of it.
enum ScrollActivity {
    private static var lastEvent: TimeInterval = 0
    private static var monitor: Any?

    /// A scroll event arrived in the last quarter of a second.
    static var isScrolling: Bool {
        ProcessInfo.processInfo.systemUptime - lastEvent < 0.25
    }

    static func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            lastEvent = ProcessInfo.processInfo.systemUptime
            FrameMonitor.shared?.scrolled()
            return event
        }
    }
}

/// Hover for cards and rows inside scrolling pages. While the page scrolls under a still
/// pointer, cards passing beneath it don't light up one after another (each would animate
/// its shadow, play button and gradient mid-scroll); leaving still ends the hover at once.
private struct ScrollAwareHover: ViewModifier {
    @Binding var hover: Bool
    let animation: Animation?

    func body(content: Content) -> some View {
        content.onContinuousHover { phase in
            let inside: Bool
            switch phase {
            case .active: inside = true
            case .ended: inside = false
            }
            guard inside != hover else { return }
            let scrolling = ScrollActivity.isScrolling
            if inside && scrolling { return }
            if scrolling || animation == nil {
                hover = inside
            } else {
                withAnimation(animation) { hover = inside }
            }
        }
    }
}

extension View {
    func scrollAwareHover(_ hover: Binding<Bool>, animation: Animation? = nil) -> some View {
        modifier(ScrollAwareHover(hover: hover, animation: animation))
    }
}

/// Diagnostics only (`diagnosticLog`): counts the frames of each scroll gesture and how many
/// came late, and writes one line per gesture to the log. Off otherwise (no display link).
final class FrameMonitor: NSObject {
    static let shared: FrameMonitor? = EngineLog.enabled ? FrameMonitor() : nil

    private var link: CADisplayLink?
    private var last: CFTimeInterval = 0
    private var frames = 0
    private var late = 0
    private var worst: CFTimeInterval = 0
    private var active = false

    func scrolled() {
        guard !active else { return }
        active = true
        frames = 0; late = 0; worst = 0; last = 0
        if link == nil, let screen = NSScreen.main {
            let l = screen.displayLink(target: self, selector: #selector(tick(_:)))
            l.add(to: .main, forMode: .common)
            link = l
        }
        link?.isPaused = false
    }

    @objc private func tick(_ l: CADisplayLink) {
        let now = l.timestamp
        let expected = max(l.duration, 1.0 / 120)
        if last > 0 {
            let gap = now - last
            frames += 1
            if gap > expected * 1.5 { late += 1; worst = max(worst, gap) }
        }
        last = now
        if !ScrollActivity.isScrolling {
            l.isPaused = true
            active = false
            if frames > 10 {
                EngineLog.write(String(format: "Kaydırma: %d kare, %d geç kare, en uzun %.0f ms (beklenen %.1f ms)",
                                       frames, late, worst * 1000, expected * 1000))
            }
        }
    }
}
