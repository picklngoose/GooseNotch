import SwiftUI

/// A single black body that grows out of the physical notch.
///
/// Collapsed it matches the notch, or widens for live activity. Expanded it is a wide body flush
/// with the top of the screen, with concave "ears" flaring outward at the top corners and rounded
/// bottom corners.
struct ConnectedIslandShape: Shape {
    var progress: CGFloat
    var activityProgress: CGFloat
    var notchWidth: CGFloat
    var notchHeight: CGFloat
    var activityWidth: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(progress, activityProgress) }
        set {
            progress = newValue.first
            activityProgress = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let p = min(max(progress, 0), 1)
        let active = min(max(activityProgress, 0), 1)
        let maxFlare = IslandMetrics.topFlare
        let flare = maxFlare * p

        let maxBodyWidth = rect.width - maxFlare * 2
        let collapsedWidth = notchWidth + (activityWidth - notchWidth) * active
        let bodyWidth = collapsedWidth + (maxBodyWidth - collapsedWidth) * p
        let bodyHeight = notchHeight + (rect.height - notchHeight) * p

        let baseRadius: CGFloat = 9
        let radius = min(
            baseRadius + (IslandMetrics.contentCornerRadius - baseRadius) * p,
            bodyHeight / 2,
            bodyWidth / 2
        )

        let cx = rect.midX
        let top = rect.minY
        let left = cx - bodyWidth / 2
        let right = cx + bodyWidth / 2
        let bottom = top + bodyHeight

        var path = Path()
        path.move(to: CGPoint(x: left - flare, y: top))
        path.addLine(to: CGPoint(x: right + flare, y: top))

        // Right ear: concave curve from the top edge into the side wall.
        if flare > 0.4 {
            path.addQuadCurve(
                to: CGPoint(x: right, y: top + flare),
                control: CGPoint(x: right, y: top)
            )
        } else {
            path.addLine(to: CGPoint(x: right, y: top))
        }

        path.addLine(to: CGPoint(x: right, y: bottom - radius))
        path.addQuadCurve(
            to: CGPoint(x: right - radius, y: bottom),
            control: CGPoint(x: right, y: bottom)
        )
        path.addLine(to: CGPoint(x: left + radius, y: bottom))
        path.addQuadCurve(
            to: CGPoint(x: left, y: bottom - radius),
            control: CGPoint(x: left, y: bottom)
        )

        // Left ear.
        if flare > 0.4 {
            path.addLine(to: CGPoint(x: left, y: top + flare))
            path.addQuadCurve(
                to: CGPoint(x: left - flare, y: top),
                control: CGPoint(x: left, y: top)
            )
        } else {
            path.addLine(to: CGPoint(x: left, y: top))
        }

        path.closeSubpath()
        return path
    }
}
