import Foundation
import CoreGraphics

// Calculs indépendants du rendu, vérifiables sans ouvrir de fenêtre.
enum SnowSurfaceMath {
    static func sameResizingSupport(_ old: CGRect, _ new: CGRect) -> Bool {
        guard abs(old.maxY - new.maxY) <= 2 else { return false }
        let sameEdge = abs(old.minX - new.minX) <= 2 || abs(old.maxX - new.maxX) <= 2
        return sameEdge && old.intersection(new).width >= min(old.width, new.width) * 0.9
    }

    static let hangTime: CGFloat = 0.9
    static let cornerInset: CGFloat = 13
    static let contactOverlap: CGFloat = 1.5
    static func supports(localX: CGFloat, width: CGFloat) -> Bool {
        localX >= cornerInset && localX <= width - cornerInset
    }
    static func supportChanged(from old: CGRect, to new: CGRect) -> Bool {
        abs(old.minX - new.minX) > 1 || abs(old.maxY - new.maxY) > 1
            || abs(old.width - new.width) > 1 || abs(old.height - new.height) > 1
    }
    static func shedFraction(from old: CGRect, to new: CGRect) -> CGFloat {
        let distance = hypot(new.minX - old.minX, new.maxY - old.maxY)
        guard distance > 3 else { return 0 }
        return min(0.75, 0.25 + distance / 500)
    }
}

struct GroundSnow {
    private(set) var heights: [CGFloat]
    let width: CGFloat
    var binWidth: CGFloat { width / CGFloat(heights.count) }
    var average: CGFloat { heights.reduce(0, +) / CGFloat(heights.count) }
    var peak: CGFloat { heights.max() ?? 0 }

    init(width: CGFloat, count: Int = 160) {
        self.width = max(1, width)
        heights = Array(repeating: 0, count: max(1, count))
    }
    mutating func add(volume: CGFloat, x: CGFloat, spread: CGFloat = 0) {
        guard x >= 0, x < width, volume > 0 else { return }
        // Une plaque large se pose sur sa largeur, pas en un point qui fait une tour.
        let radius = max(36, max(spread * 0.75, volume / 18))
        var weights: [(Int, CGFloat)] = []
        var total: CGFloat = 0
        for i in heights.indices {
            let center = (CGFloat(i) + 0.5) * binWidth
            let distance = abs(center - x) / radius
            guard distance < 1 else { continue }
            let weight = pow(cos(distance * .pi / 2), 2)
            weights.append((i, weight))
            total += weight
        }
        guard total > 0 else { return }
        for (i, weight) in weights { heights[i] += volume * weight / total / binWidth }
    }

    func height(at x: CGFloat) -> CGFloat {
        let t = max(0, min(CGFloat(heights.count - 1), x / binWidth - 0.5))
        let i = Int(t), j = min(heights.count - 1, Int(t) + 1)
        return heights[i] + (heights[j] - heights[i]) * (t - CGFloat(i))
    }

    func contourPath() -> CGPath {
        let path = CGMutablePath()
        path.move(to: .zero)
        // Courbe quadratique bornée par les hauteurs : ni pics ni dépassements.
        var previous = CGPoint(x: 0, y: heights.first ?? 0)
        path.addLine(to: previous)
        for (i, height) in heights.enumerated() {
            let point = CGPoint(x: (CGFloat(i) + 0.5) * binWidth, y: height)
            let middle = CGPoint(x: (previous.x + point.x) / 2, y: (previous.y + point.y) / 2)
            path.addQuadCurve(to: middle, control: previous)
            previous = point
        }
        let end = CGPoint(x: width, y: heights.last ?? 0)
        path.addQuadCurve(to: end, control: previous)
        path.addLine(to: CGPoint(x: width, y: 0))
        path.closeSubpath()
        return path
    }

    mutating func sweep(from start: CGFloat, to end: CGFloat) -> CGFloat {
        guard end > start else { return 0 }
        var volume: CGFloat = 0
        for i in heights.indices {
            let x = (CGFloat(i) + 0.5) * binWidth
            if x >= start && x < end {
                volume += heights[i] * binWidth
                heights[i] = 0
            }
        }
        return volume
    }
}

// Position analytique : un ralentissement du rendu ne prolonge pas la suspension.
struct SnowFallMotion {
    let origin: CGPoint
    let vx: CGFloat
    let spin: CGFloat
    let bornAt: TimeInterval
    let delay: TimeInterval

    func sample(at time: TimeInterval) -> (position: CGPoint, rotation: CGFloat, finished: Bool) {
        let elapsed = max(0, time - bornAt)
        let falling = CGFloat(max(0, elapsed - min(1.4, max(0, delay))))
        let position = CGPoint(x: origin.x + vx * falling, y: origin.y - 215 * falling * falling)
        return (position, spin * falling, position.y <= 2 || elapsed >= 8)
    }
}

// Remplit d'abord sous l'impact, puis utilise les places libres du même bord.
// Renvoie la quantité réellement retenue ; le surplus poursuit sa chute.
enum SnowLanding {
    static func absorb(volume: CGFloat, heights: inout [CGFloat], limits: [CGFloat], eligible: [Bool], x: CGFloat, footprint: CGFloat) -> CGFloat {
        guard volume > 0, heights.count == limits.count, heights.count == eligible.count else { return 0 }
        let radius = max(30, footprint * 0.65)
        let near = heights.indices.filter { eligible[$0] && abs((CGFloat($0) + 0.5) * 18 - x) <= radius }
        let far = heights.indices.filter { eligible[$0] && abs((CGFloat($0) + 0.5) * 18 - x) > radius }
        var remaining = volume
        for indices in [near, far] where remaining > 0.001 {
            let space = indices.reduce(CGFloat(0)) { $0 + max(0, limits[$1] - heights[$1]) * 18 }
            guard space > 0.001 else { continue }
            let fill = min(1, remaining / space)
            let accepted = min(space, remaining)
            for i in indices { heights[i] += max(0, limits[i] - heights[i]) * fill }
            remaining -= accepted
        }
        return volume - remaining
    }
}

// Historique borné, sans capture, titre ni contenu de fenêtre.
enum SnowDiagnostics {
    private(set) static var events: [String] = []
    static func record(_ message: String) {
        events.append(message)
        if events.count > 60 { events.removeFirst(events.count - 60) }
    }
}
