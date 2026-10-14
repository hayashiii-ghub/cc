import SwiftUI

struct ContextMark: Shape {
    func path(in rect: CGRect) -> Path {
        var letters = Path()
        letters.move(to: CGPoint(x: 9.396, y: 8.5))
        letters.addCurve(to: CGPoint(x: 6.676, y: 7), control1: CGPoint(x: 8.716, y: 7.5), control2: CGPoint(x: 7.764, y: 7))
        letters.addCurve(to: CGPoint(x: 2.8, y: 12), control1: CGPoint(x: 4.296, y: 7), control2: CGPoint(x: 2.8, y: 9.05))
        letters.addCurve(to: CGPoint(x: 6.676, y: 17), control1: CGPoint(x: 2.8, y: 14.95), control2: CGPoint(x: 4.296, y: 17))
        letters.addCurve(to: CGPoint(x: 9.396, y: 15.5), control1: CGPoint(x: 7.764, y: 17), control2: CGPoint(x: 8.716, y: 16.5))
        letters.move(to: CGPoint(x: 19.896, y: 8.5))
        letters.addCurve(to: CGPoint(x: 17.176, y: 7), control1: CGPoint(x: 19.216, y: 7.5), control2: CGPoint(x: 18.264, y: 7))
        letters.addCurve(to: CGPoint(x: 13.3, y: 12), control1: CGPoint(x: 14.796, y: 7), control2: CGPoint(x: 13.3, y: 9.05))
        letters.addCurve(to: CGPoint(x: 17.176, y: 17), control1: CGPoint(x: 13.3, y: 14.95), control2: CGPoint(x: 14.796, y: 17))
        letters.addCurve(to: CGPoint(x: 19.896, y: 15.5), control1: CGPoint(x: 18.264, y: 17), control2: CGPoint(x: 19.216, y: 16.5))

        var mark = letters.strokedPath(StrokeStyle(lineWidth: 2.8, lineCap: .round, lineJoin: .round))
        mark.addEllipse(in: CGRect(x: 23.6, y: 6.6, width: 2.8, height: 2.8))
        mark.addEllipse(in: CGRect(x: 23.6, y: 14.6, width: 2.8, height: 2.8))
        let scale = min(rect.width / 28, rect.height / 24)
        return mark.applying(CGAffineTransform(
            a: scale, b: 0, c: 0, d: scale,
            tx: rect.midX - 14 * scale, ty: rect.midY - 12 * scale
        ))
    }
}
