import Foundation
import CoreGraphics

@main
struct SnowPhysicsChecks {
    static func main() {
        let old = CGRect(x: 100, y: 100, width: 400, height: 300)
        precondition(SnowSurfaceMath.shedFraction(from: old, to: old) == 0)
        let moved = old.offsetBy(dx: 60, dy: 10)
        precondition(SnowSurfaceMath.shedFraction(from: old, to: moved) > 0.25)
        precondition(SnowSurfaceMath.shedFraction(from: old, to: old.offsetBy(dx: 2000, dy: 0)) == 0.75)
        precondition(!SnowSurfaceMath.supports(localX: 5, width: 400))
        precondition(SnowSurfaceMath.supports(localX: 30, width: 400))
        precondition(!SnowSurfaceMath.supports(localX: 380, width: 250))
        precondition(SnowSurfaceMath.contactOverlap > 0)
        var ground = GroundSnow(width: 1000, count: 100)
        ground.add(volume: 100, x: 100)
        ground.add(volume: 100, x: 800)
        precondition(abs(ground.average - 0.2) < 0.0001)
        let cleared = ground.sweep(from: -100, to: 500)
        precondition(abs(cleared - 100) < 0.0001)
        precondition(abs(ground.average - 0.1) < 0.0001)
        precondition(ground.sweep(from: 500, to: 1000) > 99)
        precondition(ground.average == 0)
        ground.add(volume: 100, x: -30)
        precondition(ground.average == 0)
        var slab = GroundSnow(width: 1000, count: 100)
        slab.add(volume: 1500, x: 500, spread: 160)
        precondition(abs(slab.average * 1000 - 1500) < 0.001)
        precondition(slab.heights.filter { $0 > 0 }.count > 15)
        precondition(slab.peak < 15)
        var edgePile = GroundSnow(width: 1000, count: 100)
        edgePile.add(volume: 1500, x: 0, spread: 160)
        precondition(abs(edgePile.average * 1000 - 1500) < 0.001)
        precondition(slab.contourPath().boundingBoxOfPath.height <= slab.peak + 0.001)
        print("18 vérifications réussies : support, détachement, matière au sol et déblaiement.")
    }
}
