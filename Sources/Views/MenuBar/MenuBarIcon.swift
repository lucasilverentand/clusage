import AppKit
import SwiftUI

struct MenuBarIcon: View {
    let accountStore: AccountStore
    private var primary: Account? {
        accountStore.menuBarAccount
    }

    private var fiveHourFraction: Double {
        primary?.fiveHour?.normalizedUtilization ?? 0
    }

    private var sevenDayFraction: Double {
        primary?.sevenDay?.normalizedUtilization ?? 0
    }

    private var accessibilityDescription: String {
        let fivePercent = Int(fiveHourFraction * 100)
        let sevenPercent = Int(sevenDayFraction * 100)
        return "Clusage: 5-hour usage \(fivePercent) percent, 7-day usage \(sevenPercent) percent"
    }

    var body: some View {
        Image(nsImage: renderIcon())
            .accessibilityLabel(accessibilityDescription)
    }

    /// Renders the dual-ring icon into an NSImage using Core Graphics.
    /// MenuBarExtra labels only reliably render Image/Text — Canvas views are silently ignored.
    private func renderIcon() -> NSImage {
        let size: CGFloat = 18
        let scale: CGFloat = 2 // Retina
        let pixelSize = Int(size * scale)

        let image = NSImage(size: NSSize(width: size, height: size))
        image.addRepresentation({
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: pixelSize,
                pixelsHigh: pixelSize,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            )!
            rep.size = NSSize(width: size, height: size)

            guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return rep }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = ctx
            let cg = ctx.cgContext

            let center = CGPoint(x: size / 2, y: size / 2)

            // Menu bar icons use .primary which is white in dark mode, black in light.
            // NSStatusBarButton template images get auto-tinted, so draw in black
            // and mark the image as template.
            let trackColor = CGColor(gray: 0, alpha: 0.35)
            let fillColor = CGColor(gray: 0, alpha: 1)

            // Outer ring: 7-day
            let outerRadius = size / 2 - 1
            drawRing(
                in: cg, center: center, radius: outerRadius, lineWidth: 2,
                fraction: sevenDayFraction, trackColor: trackColor, fillColor: fillColor
            )

            // Inner ring: 5-hour
            let innerRadius = outerRadius - 3.5
            drawRing(
                in: cg, center: center, radius: innerRadius, lineWidth: 2,
                fraction: fiveHourFraction, trackColor: trackColor, fillColor: fillColor
            )

            NSGraphicsContext.restoreGraphicsState()
            return rep
        }())

        image.isTemplate = true
        return image
    }

    private func drawRing(
        in cg: CGContext,
        center: CGPoint,
        radius: CGFloat,
        lineWidth: CGFloat,
        fraction: Double,
        trackColor: CGColor,
        fillColor: CGColor
    ) {
        cg.setLineWidth(lineWidth)
        cg.setLineCap(.round)

        // Background track (full circle)
        cg.setStrokeColor(trackColor)
        cg.addEllipse(in: CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        ))
        cg.strokePath()

        // Filled arc
        if fraction > 0 {
            cg.setStrokeColor(fillColor)
            // CG y-axis is flipped vs SwiftUI: start at top (-90°) and sweep clockwise
            let startAngle = CGFloat.pi / 2 // top in CG's flipped coords
            let endAngle = startAngle - CGFloat.pi * 2 * fraction
            cg.addArc(
                center: center,
                radius: radius,
                startAngle: startAngle,
                endAngle: endAngle,
                clockwise: true
            )
            cg.strokePath()
        }
    }
}
