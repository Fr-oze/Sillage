import Foundation
import CoreGraphics

// Lecture seule de la souris : aucune interception ni autorisation d'accessibilité.
struct WindowPollSchedule {
    private var lastQuery = -Double.infinity
    private var fastUntil: TimeInterval = 0
    private var wasPressed = false

    mutating func requestFast(at time: TimeInterval) { fastUntil = max(fastUntil, time + 0.4); lastQuery = -Double.infinity }
    mutating func noteGeometryChange(at time: TimeInterval) { fastUntil = max(fastUntil, time + 0.4) }
    func isFast(at time: TimeInterval) -> Bool { time < fastUntil }

    mutating func shouldSample(at time: TimeInterval, pressed: Bool) -> Bool {
        if pressed && !wasPressed { requestFast(at: time) }
        if pressed { fastUntil = max(fastUntil, time + 0.4) }
        if wasPressed && !pressed { fastUntil = max(fastUntil, time + 0.4) }
        wasPressed = pressed
        let interval: TimeInterval = time < fastUntil ? 1.0 / 30.0 : 1
        guard time - lastQuery >= interval - (time < fastUntil ? 0.006 : 0.001) else { return false }
        lastQuery = time
        return true
    }
}

enum SnowSweep {
    static func crossing(from: CGPoint, to: CGPoint, plane: CGFloat, previousTop: CGFloat? = nil) -> CGFloat? {
        guard to.y < from.y, to.y <= plane + 0.001 else { return nil }
        if from.y >= plane - 0.001 { return min(1, max(0, (from.y - plane) / (from.y - to.y))) }
        if let top = previousTop, top >= plane { return 0 }
        return nil
    }
}
