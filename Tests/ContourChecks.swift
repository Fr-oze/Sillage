import Foundation
import CoreGraphics

@main
struct ContourChecks {
    static func main() {
        let heights: [CGFloat] = (0..<60).map { SnowContour.capacity(x: (CGFloat($0) + 0.5) * 18, seed: 42, dock: false) }
        precondition(heights.max()! - heights.min()! > 8, "Le relief doit subsister à saturation")
        let polygons = SnowContour.polygons(width: 1000, heights: heights, spans: [0...1000])
        precondition(polygons.count == 1)
        let originalArea = polygons.reduce(CGFloat(0)) { $0 + SnowContour.area($1) }
        var pieces: [[CGPoint]] = []
        for i in 0..<7 {
            pieces.append(contentsOf: polygons.map {
                SnowContour.clip($0, left: CGFloat(i) * 1000 / 7, right: CGFloat(i + 1) * 1000 / 7)
            })
        }
        let detachedArea = pieces.reduce(CGFloat(0)) { $0 + SnowContour.area($1) }
        precondition(abs(detachedArea - originalArea) < 0.001, "Les plaques doivent conserver exactement la matière affichée")
        let retained = SnowContour.clip(polygons[0], left: 0, right: 387)
        let dropped = SnowContour.clip(polygons[0], left: 387, right: 1000)
        precondition(abs(SnowContour.area(retained) + SnowContour.area(dropped) - originalArea) < 0.001)
        precondition(dropped.allSatisfy { $0.x >= 387 })
        precondition(retained.allSatisfy { $0.x <= 387 })
        precondition(SnowContour.polygons(width: 1000, heights: Array(repeating: 0, count: 60), spans: [0...1000]).isEmpty)
        let gapped = SnowContour.polygons(width: 1000, heights: heights, spans: [0...300, 600...1000])
        precondition(gapped.count == 2)
        precondition(gapped[0].allSatisfy { $0.x <= 300 } && gapped[1].allSatisfy { $0.x >= 600 })
        let partial = SnowContour.visiblePolygons(polygons, spans: [0...300, 600...1000])
        let hidden = SnowContour.visiblePolygons(polygons, spans: [])
        let restored = SnowContour.visiblePolygons(polygons, spans: [0...1000])
        precondition(partial.count == 2)
        precondition(hidden.isEmpty)
        precondition(abs(restored.reduce(0) { $0 + SnowContour.area($1) } - originalArea) < 0.001)
        precondition(partial[0].filter { abs($0.x - 300) < 0.01 }.map(\.y).max()! > 2,
                     "Un bord recouvert ne doit pas arrondir ou vider le profil restant")
        precondition(partial[1].allSatisfy { $0.x >= 600 })
        print("14 vérifications réussies : relief à saturation, découpe exacte, conservation de matière et rétrécissement.")
    }
}
