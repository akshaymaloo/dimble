import SwiftUI

/// The app icon's D mark, drawn natively and animated: the two ghost dots tuck
/// into the D and return, on the same 5.7s cycle as the hero SVG and the
/// onboarding bar loop. Geometry mirrors `AppIcon.icon` (1024 viewBox).
struct AnimatedAppIcon: View {
    var size: CGFloat = 96

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct DotPhases {
        var d1: CGFloat = 0  // 0 = home, 1 = tucked into the D
        var d2: CGFloat = 0
    }

    var body: some View {
        Group {
            if reduceMotion {
                icon(DotPhases())
            } else {
                KeyframeAnimator(initialValue: DotPhases()) { phases in
                    icon(phases)
                } keyframes: { _ in
                    // Expanded is the true icon; the collapse is a brief accent.
                    // Rest expanded, quick tuck, short beat, re-expand, rest.
                    // 5.7s total keeps the brand cycle; d2 trails d1 by 0.05s.
                    KeyframeTrack(\.d1) {
                        CubicKeyframe(0, duration: 3.4)
                        CubicKeyframe(1, duration: 0.45)
                        CubicKeyframe(1, duration: 0.4)
                        CubicKeyframe(0, duration: 0.45)
                        CubicKeyframe(0, duration: 1.0)
                    }
                    KeyframeTrack(\.d2) {
                        CubicKeyframe(0, duration: 3.45)
                        CubicKeyframe(1, duration: 0.45)
                        CubicKeyframe(1, duration: 0.4)
                        CubicKeyframe(0, duration: 0.45)
                        CubicKeyframe(0, duration: 0.95)
                    }
                }
            }
        }
        .frame(width: size, height: size)
    }

    private func icon(_ phases: DotPhases) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                .fill(Color(red: 0x68 / 255, green: 0x41 / 255, blue: 0xED / 255))
            Canvas { ctx, canvasSize in
                ctx.scaleBy(x: canvasSize.width / 1024, y: canvasSize.height / 1024)
                ctx.fill(Self.dPath, with: .color(.white))
                ctx.fill(Self.solidDot, with: .color(.white))
                drawGhost(Self.ghost1, into: &ctx, phase: phases.d1, travel: 96.574, restOpacity: 0.65)
                drawGhost(Self.ghost2, into: &ctx, phase: phases.d2, travel: 193.148, restOpacity: 0.3)
            }
        }
    }

    private func drawGhost(_ path: Path, into ctx: inout GraphicsContext, phase: CGFloat, travel: CGFloat, restOpacity: CGFloat) {
        var layer = ctx
        layer.translateBy(x: phase * travel, y: 0)
        layer.opacity = restOpacity * (1 - phase)
        layer.fill(path, with: .color(.white))
    }

    // MARK: - Geometry (icon SVG's 1024 space)

    private static let dPath: Path = {
        var p = Path()
        p.move(to: CGPoint(x: 294.4, y: 324.35))
        p.addLine(to: CGPoint(x: 533.541, y: 324.35))
        p.addCurve(to: CGPoint(x: 733.6, y: 512),
                   control1: CGPoint(x: 667.163, y: 324.35),
                   control2: CGPoint(x: 733.6, y: 411.073))
        p.addCurve(to: CGPoint(x: 533.541, y: 699.65),
                   control1: CGPoint(x: 733.6, y: 612.927),
                   control2: CGPoint(x: 667.163, y: 699.65))
        p.addLine(to: CGPoint(x: 294.4, y: 699.65))
        p.addLine(to: CGPoint(x: 294.4, y: 591.2))
        p.addLine(to: CGPoint(x: 533.541, y: 591.2))
        p.addCurve(to: CGPoint(x: 617.148, y: 512),
                   control1: CGPoint(x: 588.781, y: 591.2),
                   control2: CGPoint(x: 617.148, y: 553.841))
        p.addCurve(to: CGPoint(x: 533.541, y: 432.8),
                   control1: CGPoint(x: 617.148, y: 470.159),
                   control2: CGPoint(x: 588.781, y: 432.8))
        p.addLine(to: CGPoint(x: 294.4, y: 432.8))
        p.closeSubpath()
        return p
    }()

    private static let solidDot = Path(ellipseIn: CGRect(x: 537.948 - 50.4, y: 512 - 50.4, width: 100.8, height: 100.8))

    /// Ghost dots are circles carved so they never overlap their neighbor
    /// (matches the moon shapes in the source SVG).
    private static let ghost1 = carvedDot(center: CGPoint(x: 441.374, y: 512), radius: 50.4,
                                          neighbor: CGPoint(x: 537.948, y: 512), clearance: 73.8)
    private static let ghost2 = carvedDot(center: CGPoint(x: 344.8, y: 512), radius: 50.4,
                                          neighbor: CGPoint(x: 441.374, y: 512), clearance: 73.8)

    private static func carvedDot(center: CGPoint, radius: CGFloat, neighbor: CGPoint, clearance: CGFloat) -> Path {
        let dot = CGPath(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                           width: radius * 2, height: radius * 2), transform: nil)
        let carve = CGPath(ellipseIn: CGRect(x: neighbor.x - clearance, y: neighbor.y - clearance,
                                             width: clearance * 2, height: clearance * 2), transform: nil)
        return Path(dot.subtracting(carve))
    }
}
