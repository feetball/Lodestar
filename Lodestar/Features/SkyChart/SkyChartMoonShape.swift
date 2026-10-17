import Foundation

/// The shape of the Moon's lit part, for the Moon marker on the chart.
enum SkyChartMoonShape {
    /// The outline of the lit part of a disc, as screen points.
    ///
    /// The limb on the Sun's side is a half circle; the terminator is a half ellipse that bulges
    /// towards the Sun for a crescent and away from it for a gibbous Moon.
    ///
    /// - Parameters:
    ///   - center: The disc's centre.
    ///   - radius: The disc's radius.
    ///   - fraction: The lit fraction of the disc, 0 (new) to 1 (full).
    ///   - angle: The direction of the Sun from the Moon on the screen, in radians (x right, y down).
    static func litOutline(center: CGPoint, radius: CGFloat, fraction: Double,
                           towardsSun angle: Double) -> [CGPoint] {
        let cosine = CGFloat(cos(angle)), sine = CGFloat(sin(angle))
        func place(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: center.x + x * cosine - y * sine, y: center.y + x * sine + y * cosine)
        }
        let reach = radius * CGFloat(1 - 2 * min(max(fraction, 0), 1))
        let steps = 24
        var outline: [CGPoint] = []
        outline.reserveCapacity(2 * steps + 2)
        for step in 0...steps {
            let t = -Double.pi / 2 + Double.pi * Double(step) / Double(steps)
            outline.append(place(radius * CGFloat(cos(t)), radius * CGFloat(sin(t))))
        }
        for step in 0...steps {
            let t = Double.pi * Double(step) / Double(steps)
            outline.append(place(reach * CGFloat(sin(t)), radius * CGFloat(cos(t))))
        }
        return outline
    }
}
