#!/usr/bin/env python3
"""Keep the app icon, menu-bar SVG, SwiftUI mark, and site on the same cc: geometry."""

import json
from pathlib import Path
import subprocess
import tempfile


PROJECT_DIR = Path(__file__).resolve().parent.parent
START = (13.5, 8.5)
CURVES = (
    ((12.5, 7.5), (11.1, 7.0), (9.5, 7.0)),
    ((6.0, 7.0), (3.8, 9.05), (3.8, 12.0)),
    ((3.8, 14.95), (6.0, 17.0), (9.5, 17.0)),
    ((11.1, 17.0), (12.5, 16.5), (13.5, 15.5)),
)
LETTER_OFFSETS = (0.0, 10.5)
DOT_CENTERS = ((25.0, 8.0), (25.0, 16.0))
STROKE_WIDTH = 2.8
DOT_RADIUS = 1.4
VIEW_WIDTH = 28
VIEW_HEIGHT = 24


def number(value):
    return f"{value:g}"


def point(value):
    return " ".join(number(coordinate) for coordinate in value)


def letter_point(value, offset):
    return ((value[0] - 3.8) * 0.68 + 2.8 + offset, value[1])


def c_path(color, offset):
    data = "M " + point(letter_point(START, offset))
    for curve in CURVES:
        data += " C " + " ".join(point(letter_point(value, offset)) for value in curve)
    return (
        f'  <path d="{data}" fill="none" stroke="{color}" '
        f'stroke-width="{number(STROKE_WIDTH)}" stroke-linecap="round" stroke-linejoin="round"/>'
    )


def letters(color):
    return "\n".join(c_path(color, offset) for offset in LETTER_OFFSETS)


def outlined_letters(color):
    paths = []
    for offset in LETTER_OFFSETS:
        points = [letter_point(START, offset)]
        for curve in CURVES:
            points.extend(letter_point(value, offset) for value in curve)
        paths.append(points)

    # Closed contours keep Icon Composer from shading the implicit closure of open strokes.
    program = r'''
import CoreGraphics
import Foundation

let input = FileHandle.standardInput.readDataToEndOfFile()
let geometry = try JSONSerialization.jsonObject(with: input) as! [String: Any]
let paths = geometry["paths"] as! [[[Double]]]
let width = geometry["width"] as! Double
let path = CGMutablePath()
for points in paths {
    path.move(to: CGPoint(x: points[0][0], y: points[0][1]))
    for index in stride(from: 1, to: points.count, by: 3) {
        path.addCurve(
            to: CGPoint(x: points[index + 2][0], y: points[index + 2][1]),
            control1: CGPoint(x: points[index][0], y: points[index][1]),
            control2: CGPoint(x: points[index + 1][0], y: points[index + 1][1])
        )
    }
}
let outline = path.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 10)
func number(_ value: CGFloat) -> String {
    String(format: "%.8f", Double(value)).replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression)
}
func point(_ value: CGPoint) -> String { "\(number(value.x)) \(number(value.y))" }
var commands: [String] = []
outline.applyWithBlock { pointer in
    let element = pointer.pointee
    switch element.type {
    case .moveToPoint: commands.append("M " + point(element.points[0]))
    case .addLineToPoint: commands.append("L " + point(element.points[0]))
    case .addQuadCurveToPoint: commands.append("Q " + point(element.points[0]) + " " + point(element.points[1]))
    case .addCurveToPoint: commands.append("C " + point(element.points[0]) + " " + point(element.points[1]) + " " + point(element.points[2]))
    case .closeSubpath: commands.append("Z")
    @unknown default: fatalError("Unknown path element")
    }
}
print(commands.joined(separator: " "))
'''
    with tempfile.TemporaryDirectory(prefix="cc-mark-outline-") as cache:
        result = subprocess.run(
            ["swift", "-module-cache-path", cache, "-e", program],
            input=json.dumps({"width": STROKE_WIDTH, "paths": paths}),
            text=True, capture_output=True, check=True,
        )
    return f'  <path d="{result.stdout.strip()}" fill="{color}"/>'


def colon(color):
    return "\n".join(
        f'  <circle cx="{number(x)}" cy="{number(y)}" r="{number(DOT_RADIUS)}" fill="{color}"/>'
        for x, y in DOT_CENTERS
    )


def svg(size, title, contents, view_box=None):
    if view_box is None:
        view_box = f"0 0 {VIEW_WIDTH} {VIEW_HEIGHT}"
    return (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" '
        f'viewBox="{view_box}" shape-rendering="geometricPrecision">\n'
        f'  <title>{title}</title>\n{contents}\n</svg>\n'
    )


def swift_point(value):
    return f"CGPoint(x: {number(value[0])}, y: {number(value[1])})"


def swift_shape():
    commands = []
    for offset in LETTER_OFFSETS:
        commands.append(f"        letters.move(to: {swift_point(letter_point(START, offset))})")
        for control1, control2, end in CURVES:
            commands.append(
                f"        letters.addCurve(to: {swift_point(letter_point(end, offset))}, "
                f"control1: {swift_point(letter_point(control1, offset))}, control2: {swift_point(letter_point(control2, offset))})"
            )
    dots = "\n".join(
        f"        mark.addEllipse(in: CGRect(x: {number(x - DOT_RADIUS)}, "
        f"y: {number(y - DOT_RADIUS)}, width: {number(DOT_RADIUS * 2)}, height: {number(DOT_RADIUS * 2)}))"
        for x, y in DOT_CENTERS
    )
    return """import SwiftUI

struct CCMark: Shape {
    func path(in rect: CGRect) -> Path {
        var letters = Path()
""" + "\n".join(commands) + f"""

        var mark = letters.strokedPath(StrokeStyle(lineWidth: {number(STROKE_WIDTH)}, lineCap: .round, lineJoin: .round))
{dots}
        let scale = min(rect.width / {VIEW_WIDTH}, rect.height / {VIEW_HEIGHT})
        return mark.applying(CGAffineTransform(
            a: scale, b: 0, c: 0, d: scale,
            tx: rect.midX - {VIEW_WIDTH / 2:g} * scale, ty: rect.midY - {VIEW_HEIGHT / 2:g} * scale
        ))
    }}
}}
"""


def main():
    assets = PROJECT_DIR / "Assets"
    icon = assets / "cc.icon"
    (assets / "MenuBarTemplate.svg").write_text(svg(24, "cc: menu bar mark", letters("#000") + "\n" + colon("#000")))
    (icon / "Assets/01-cc.svg").write_text(svg(1024, "cc: letters", letters("#f2f3f1"), "-1.5 -1.3 31 26.6"))
    (icon / "Assets/02-colon.svg").write_text(svg(1024, "cc: colon", colon("#e8eeee"), "-1.5 -1.3 31 26.6"))
    (icon / "Assets/01-cc-light.svg").write_text(svg(1024, "cc: letters", outlined_letters("#0b0b0d"), "-1.5 -1.3 31 26.6"))
    (icon / "Assets/02-colon-light.svg").write_text(svg(1024, "cc: colon", colon("#0b0b0d"), "-1.5 -1.3 31 26.6"))
    (PROJECT_DIR / "site/public/cc/cc-mark.svg").write_text(
        svg(1024, "cc: mark", letters("#f2f3f1") + "\n" + colon("#e8eeee"))
    )
    (PROJECT_DIR / "Sources/CC/Support/CCMark.swift").write_text(swift_shape())


if __name__ == "__main__":
    main()
