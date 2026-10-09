import AppKit

@MainActor
final class NotchHoverMonitor {
    var onHoverChange: ((Bool) -> Void)?

    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var geometry: NotchGeometry?
    private var isExpanded = false
    private var expandedHeight = IslandMetrics.expandedSize.height
    private var collapseWork: DispatchWorkItem?
    private var lastInside = false

    func start() {
        stop()
        let handler: (NSEvent) -> Void = { [weak self] _ in
            self?.evaluate()
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]) { event in
            handler(event)
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged], handler: handler)
    }

    func stop() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        collapseWork?.cancel()
    }

    func update(geometry: NotchGeometry, isExpanded: Bool, expandedHeight: CGFloat? = nil) {
        self.geometry = geometry
        self.isExpanded = isExpanded
        if let expandedHeight { self.expandedHeight = expandedHeight }
        evaluate()
    }

    private func evaluate() {
        guard let geometry else { return }
        let point = NSEvent.mouseLocation
        let inside = geometry.hoverFrame.contains(point) || geometry.expandedHitFrame(isExpanded: isExpanded, height: expandedHeight).contains(point)

        if inside {
            collapseWork?.cancel()
            collapseWork = nil
            if !lastInside {
                lastInside = true
                onHoverChange?(true)
            }
        } else if lastInside {
            // Collapse the moment the cursor leaves.
            collapseWork?.cancel()
            collapseWork = nil
            lastInside = false
            onHoverChange?(false)
        }
    }
}
