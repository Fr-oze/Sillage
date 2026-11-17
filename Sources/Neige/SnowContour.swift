import Foundation
import CoreGraphics

// Le même contour sert au dépôt et aux plaques qui se détachent.
enum SnowContour {
    static func capacity(x: CGFloat, seed: UInt32, dock: Bool) -> CGFloat {
        let phase = CGFloat(seed % 101) * 0.31
        let relief = 4.5 * sin(x * 0.018 + phase) + 2.1 * sin(x * 0.049 + phase * 1.7)
            + 0.8 * sin(x * 0.115 + phase * 0.6)
        return max(3, (dock ? 7 : 11) + relief * (dock ? 0.65 : 1))
    }

    static func height(at x: CGFloat, heights: [CGFloat]) -> CGFloat {
        guard !heights.isEmpty else { return 0 }
        let t = max(0, x / 18 - 0.5)
        let i = Int(t)
        let f = t - CGFloat(i)
        func h(_ index: Int) -> CGFloat { heights[max(0, min(heights.count - 1, index))] }
        // Interpolation lisse, sans les marches des anciennes cellules.
        let p0 = h(i - 1), p1 = h(i), p2 = h(i + 1), p3 = h(i + 2)
        return max(0, 0.5 * ((2 * p1) + (-p0 + p2) * f + (2 * p0 - 5 * p1 + 4 * p2 - p3) * f * f
                            + (-p0 + 3 * p1 - 3 * p2 + p3) * f * f * f))
    }

    static func polygons(width: CGFloat, heights: [CGFloat], spans: [ClosedRange<CGFloat>]) -> [[CGPoint]] {
        var result: [[CGPoint]] = []
        for span in spans {
            let left = max(SnowSurfaceMath.cornerInset, span.lowerBound)
            let right = min(width - SnowSurfaceMath.cornerInset, span.upperBound)
            guard right - left > 3 else { continue }
            let count = max(2, Int(ceil((right - left) / 3)))
            var polygon = [CGPoint(x: left, y: 0)]
            for i in 0...count {
                let x = left + (right - left) * CGFloat(i) / CGFloat(count)
                let ramp = max(0, min(1, min(x - left, right - x) / 8))
                let edge = sin(ramp * .pi / 2)
                polygon.append(CGPoint(x: x, y: height(at: x, heights: heights) * edge))
            }
            polygon.append(CGPoint(x: right, y: 0))
            if area(polygon) > 0.1 { result.append(polygon) }
        }
        return result
    }

    // Le profil complet reste stocké même lorsqu'une fenêtre passe devant.
    // Le bord du masque ne devient pas un nouveau coin arrondi du tas.
    static func visiblePolygons(_ polygons: [[CGPoint]], spans: [ClosedRange<CGFloat>]) -> [[CGPoint]] {
        spans.flatMap { span in
            polygons.map { clip($0, left: span.lowerBound, right: span.upperBound) }
                .filter { area($0) > 0.1 }
        }
    }

    // Découpe vectorielle exacte : les sommets du toit ne sont pas redessinés.
    static func clip(_ polygon: [CGPoint], left: CGFloat, right: CGFloat) -> [CGPoint] {
        guard left < right else { return [] }
        func cut(_ input: [CGPoint], boundary: CGFloat, keepRight: Bool) -> [CGPoint] {
            guard let last = input.last else { return [] }
            var result: [CGPoint] = []
            var previous = last
            for current in input {
                let currentInside = keepRight ? current.x >= boundary : current.x <= boundary
                let previousInside = keepRight ? previous.x >= boundary : previous.x <= boundary
                if currentInside != previousInside {
                    let t = (boundary - previous.x) / (current.x - previous.x)
                    result.append(CGPoint(x: boundary, y: previous.y + t * (current.y - previous.y)))
                }
                if currentInside { result.append(current) }
                previous = current
            }
            return result
        }
        return cut(cut(polygon, boundary: left, keepRight: true), boundary: right, keepRight: false)
    }

    static func clipAbove(_ polygon: [CGPoint], y: CGFloat) -> [CGPoint] {
        guard let last = polygon.last else { return [] }
        var result: [CGPoint] = []
        var previous = last
        for current in polygon {
            if (previous.y >= y) != (current.y >= y) {
                let t = (y - previous.y) / (current.y - previous.y)
                result.append(CGPoint(x: previous.x + t * (current.x - previous.x), y: y))
            }
            if current.y >= y { result.append(current) }
            previous = current
        }
        return result
    }

    static func removingBottomArea(_ polygons: [[CGPoint]], area removed: CGFloat) -> [[CGPoint]] {
        let total = polygons.reduce(CGFloat(0)) { $0 + area($1) }
        if removed >= total - 0.001 { return [] }
        if removed <= 0 { return polygons }
        let points = polygons.flatMap { $0 }
        var low = points.map(\.y).min() ?? 0
        var high = points.map(\.y).max() ?? 0
        let target = total - removed
        for _ in 0..<28 {
            let middle = (low + high) / 2
            let remaining = polygons.reduce(CGFloat(0)) { $0 + area(clipAbove($1, y: middle)) }
            if remaining > target { low = middle } else { high = middle }
        }
        return polygons.map { clipAbove($0, y: (low + high) / 2) }.filter { area($0) > 0.001 }
    }

    static func transformed(_ polygons: [[CGPoint]], position: CGPoint, angle: CGFloat, inverse: Bool = false) -> [[CGPoint]] {
        let c = cos(angle), s = sin(angle)
        return polygons.map { polygon in polygon.map { point in
            if inverse {
                let x = point.x - position.x, y = point.y - position.y
                return CGPoint(x: c * x + s * y, y: -s * x + c * y)
            }
            return CGPoint(x: position.x + c * point.x - s * point.y, y: position.y + s * point.x + c * point.y)
        } }
    }

    static func bounds(_ polygons: [[CGPoint]]) -> CGRect {
        let points = polygons.flatMap { $0 }
        guard let x = points.map(\.x).min(), let y = points.map(\.y).min(),
              let right = points.map(\.x).max(), let top = points.map(\.y).max() else { return .null }
        return CGRect(x: x, y: y, width: right - x, height: top - y)
    }

    static func area(_ polygon: [CGPoint]) -> CGFloat {
        guard polygon.count >= 3 else { return 0 }
        var sum: CGFloat = 0
        for i in polygon.indices {
            let next = polygon[(i + 1) % polygon.count]
            sum += polygon[i].x * next.y - next.x * polygon[i].y
        }
        return abs(sum) / 2
    }

    static func path(_ polygons: [[CGPoint]], offset: CGPoint = .zero) -> CGPath {
        let path = CGMutablePath()
        for polygon in polygons where polygon.count >= 3 {
            path.move(to: CGPoint(x: polygon[0].x + offset.x, y: polygon[0].y + offset.y))
            for point in polygon.dropFirst() { path.addLine(to: CGPoint(x: point.x + offset.x, y: point.y + offset.y)) }
            path.closeSubpath()
        }
        return path
    }
}
