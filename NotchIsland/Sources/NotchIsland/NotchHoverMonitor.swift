import AppKit

@MainActor
final class NotchHoverMonitor {
    var onHoverChange: ((Bool) -> Void)?
    var onRightClick: (() -> Void)?

    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var localRightClickMonitor: Any?
    private var globalRightClickMonitor: Any?
    private var geometry: NotchGeometry?
    private var isExpanded = false
    private var isActive = false
    private var expandedHeight = IslandMetrics.expandedSize.height
    private var expandedWidth = IslandMetrics.expandedSize.width
    private var activityWingWidth = IslandMetrics.activityWingWidth
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
        localRightClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
            self?.handleRightClick()
            return event
        }
        globalRightClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .rightMouseDown) { [weak self] _ in
            self?.handleRightClick()
        }
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
        if let localRightClickMonitor {
            NSEvent.removeMonitor(localRightClickMonitor)
            self.localRightClickMonitor = nil
        }
        if let globalRightClickMonitor {
            NSEvent.removeMonitor(globalRightClickMonitor)
            self.globalRightClickMonitor = nil
        }
        collapseWork?.cancel()
    }

    func update(
        geometry: NotchGeometry,
        isExpanded: Bool,
        isActive: Bool = false,
        expandedHeight: CGFloat? = nil,
        expandedWidth: CGFloat? = nil,
        activityWingWidth: CGFloat? = nil
    ) {
        self.geometry = geometry
        self.isExpanded = isExpanded
        self.isActive = isActive
        if let expandedHeight { self.expandedHeight = expandedHeight }
        if let expandedWidth { self.expandedWidth = expandedWidth }
        if let activityWingWidth { self.activityWingWidth = activityWingWidth }
        evaluate()
    }

    private func handleRightClick() {
        guard !isExpanded,
              let geometry,
              geometry.notchFrame.contains(NSEvent.mouseLocation)
        else {
            return
        }
        onRightClick?()
    }

    private func evaluate() {
        guard let geometry else { return }
        let point = NSEvent.mouseLocation
        let inside = geometry.hoverFrame(isActive: isActive, activityWingWidth: activityWingWidth).contains(point)
            || geometry.expandedHitFrame(
                isExpanded: isExpanded,
                isActive: isActive,
                height: expandedHeight,
                width: expandedWidth,
                activityWingWidth: activityWingWidth
            ).contains(point)

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
