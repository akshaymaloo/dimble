// HouseEasing.swift
// The house's two curves, from the design mock: in on a quick start and a
// long settle, out on a slow start that speeds away. One definition for
// every form the panels animate with (AppKit's timing function, SwiftUI's
// animation and unit curve), so a retune is one edit.

import AppKit
import SwiftUI

enum HouseEasing {
    typealias Points = (x1: Double, y1: Double, x2: Double, y2: Double)

    static let enterPoints: Points = (0.16, 1, 0.3, 1)
    static let exitPoints: Points = (0.55, 0, 0.8, 0.4)

    static var enterTiming: CAMediaTimingFunction { timing(enterPoints) }
    static var exitTiming: CAMediaTimingFunction { timing(exitPoints) }

    /// For a motion stepped by hand.
    static let enterCurve = unitCurve(enterPoints)
    static let exitCurve = unitCurve(exitPoints)

    static func enter(_ duration: TimeInterval) -> Animation { animation(enterPoints, duration) }
    static func exit(_ duration: TimeInterval) -> Animation { animation(exitPoints, duration) }

    private static func timing(_ p: Points) -> CAMediaTimingFunction {
        CAMediaTimingFunction(controlPoints: Float(p.x1), Float(p.y1), Float(p.x2), Float(p.y2))
    }

    private static func unitCurve(_ p: Points) -> UnitCurve {
        .bezier(startControlPoint: UnitPoint(x: p.x1, y: p.y1), endControlPoint: UnitPoint(x: p.x2, y: p.y2))
    }

    private static func animation(_ p: Points, _ duration: TimeInterval) -> Animation {
        .timingCurve(p.x1, p.y1, p.x2, p.y2, duration: duration)
    }
}
