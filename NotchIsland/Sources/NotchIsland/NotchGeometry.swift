import AppKit

struct NotchGeometry: Equatable {
    let screenID: CGDirectDisplayID
    let screenFrame: NSRect
    let notchFrame: NSRect
    let usingPhysicalNotch: Bool

    var centerX: CGFloat { notchFrame.midX }
    var notchSize: NSSize { notchFrame.size }

    /// Slightly larger than the visible collapsed shape so hover is easy to hit.
    func hoverFrame(
        isActive: Bool = false,
        activityWingWidth: CGFloat = IslandMetrics.activityWingWidth
    ) -> NSRect {
        let horizontalInset = isActive ? activityWingWidth + 10 : 10
        return notchFrame.insetBy(dx: -horizontalInset, dy: -8)
    }

    var windowFrame: NSRect {
        let size = IslandMetrics.windowSize
        return NSRect(
            x: (centerX - size.width / 2).rounded(.toNearestOrAwayFromZero),
            y: (screenFrame.maxY - size.height).rounded(.toNearestOrAwayFromZero),
            width: size.width,
            height: size.height
        )
    }

    func expandedHitFrame(
        isExpanded: Bool,
        isActive: Bool = false,
        height: CGFloat = IslandMetrics.expandedSize.height,
        width: CGFloat = IslandMetrics.expandedSize.width,
        activityWingWidth: CGFloat = IslandMetrics.activityWingWidth
    ) -> NSRect {
        guard isExpanded else { return hoverFrame(isActive: isActive, activityWingWidth: activityWingWidth) }
        let size = NSSize(width: width, height: height)
        // Match the visible body exactly (the flared ears are only a few points tall).
        let bodyWidth = size.width - IslandMetrics.topFlare * 2
        return NSRect(
            x: centerX - bodyWidth / 2,
            y: screenFrame.maxY - size.height,
            width: bodyWidth,
            height: size.height
        )
    }

    static func current() -> NotchGeometry? {
        let mouseScreen = screenContaining(NSEvent.mouseLocation) ?? NSScreen.main
        let notched = NSScreen.screens.first { physicalNotchFrame(on: $0) != nil }
        let screen = notched ?? mouseScreen ?? NSScreen.screens.first
        guard let screen else { return nil }

        let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0

        if let notch = physicalNotchFrame(on: screen) {
            return NotchGeometry(
                screenID: displayID,
                screenFrame: screen.frame,
                notchFrame: notch,
                usingPhysicalNotch: true
            )
        }

        // No camera housing on this display: still offer a top-center hover zone
        // without drawing a fake notch while idle.
        return NotchGeometry(
            screenID: displayID,
            screenFrame: screen.frame,
            notchFrame: fallbackHoverFrame(on: screen),
            usingPhysicalNotch: false
        )
    }

    static func physicalNotchFrame(on screen: NSScreen) -> NSRect? {
        guard screen.safeAreaInsets.top > 0,
              let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea
        else {
            return nil
        }

        let width = right.minX - left.maxX
        let height = screen.safeAreaInsets.top
        guard width > 8, height > 8 else { return nil }

        return NSRect(
            x: left.maxX,
            y: screen.frame.maxY - height,
            width: width,
            height: height
        )
    }

    private static func fallbackHoverFrame(on screen: NSScreen) -> NSRect {
        let menuHeight = max(screen.frame.maxY - screen.visibleFrame.maxY, 24)
        let width: CGFloat = 180
        return NSRect(
            x: screen.frame.midX - width / 2,
            y: screen.frame.maxY - menuHeight,
            width: width,
            height: menuHeight
        )
    }

    private static func screenContaining(_ point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) }
    }
}

enum IslandMetrics {
    // Taller than the original so the transcript has room.
    static let expandedSize = NSSize(width: 540, height: 184)
    static let activityWingWidth: CGFloat = 78
    static let chatHeight: CGFloat = 236
    // Tall enough for the largest tab (chat) plus a little margin.
    static let windowSize = NSSize(width: 572, height: 256)
    static let contentCornerRadius: CGFloat = 26
    static let topFlare: CGFloat = 14
    static let islandFill = NSColor.black
}
