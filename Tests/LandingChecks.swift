import AppKit
import SpriteKit

@main
struct LandingChecks {
    static func main() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 900)
        let upper = SnowLedge(id: 1, frame: CGRect(x: 100, y: 500, width: 600, height: 200), spans: [100...700], isDock: false)
        func receiver(_ id: UInt32, top: CGFloat, full: Bool = false, hidden: Bool = false) -> SnowLedge {
            SnowLedge(id: id, frame: CGRect(x: 50, y: top - 150, width: 850, height: 150),
                      spans: hidden ? [] : [50...900], isDock: false, maxSnowHeight: full ? 2.3 : 20)
        }
        func fixture(_ others: [SnowLedge]) -> (SnowDeposits, SKScene) {
            let scene = SKScene(size: screen.size)
            let snow = SnowDeposits(settlingDelay: 0)
            snow.configure(enabled: true, automaticPlow: false, scene: scene)
            snow.step(at: 0, scene: scene)
            for _ in 0..<12 { snow.update(ledges: [upper] + others, screenFrame: screen, scene: scene, amount: 0.5) }
            snow.update(ledges: others, screenFrame: screen, scene: scene, amount: 0.5)
            return (snow, scene)
        }
        let lower = receiver(2, top: 400)
        let (snow, scene) = fixture([lower])
        let oldHeight = (scene.children[1] as! SKShapeNode).path!.boundingBoxOfPath.height
        snow.step(at: 4, scene: scene)
        precondition(scene.children.count == 2, "La plaque doit être retenue par la fenêtre inférieure")
        precondition((scene.children[0] as! SKShapeNode).path == nil, "La neige retenue ne doit pas arriver au sol")
        precondition((scene.children[1] as! SKShapeNode).path!.boundingBoxOfPath.height > oldHeight)

        let full = receiver(2, top: 400, full: true)
        let lowest = receiver(3, top: 180)
        let (chain, chainScene) = fixture([full, lowest])
        let oldLowest = (chainScene.children[2] as! SKShapeNode).path!.boundingBoxOfPath.height
        chain.step(at: 4, scene: chainScene)
        precondition(chainScene.children.count == 3)
        precondition((chainScene.children[0] as! SKShapeNode).path == nil)
        precondition((chainScene.children[2] as! SKShapeNode).path!.boundingBoxOfPath.height > oldLowest,
                     "Un bord plein doit laisser le surplus atteindre le bord suivant")

        let (floorOnly, floorScene) = fixture([full])
        floorOnly.step(at: 4, scene: floorScene)
        precondition((floorScene.children[0] as! SKShapeNode).path != nil)
        let (covered, coveredScene) = fixture([receiver(2, top: 400, hidden: true)])
        covered.step(at: 4, scene: coveredScene)
        precondition((coveredScene.children[0] as! SKShapeNode).path != nil,
                     "Un bord recouvert ne doit pas attraper la neige")

        var heights: [CGFloat] = [1, 1, 1]
        let accepted = SnowLanding.absorb(volume: 200, heights: &heights, limits: [2, 2, 2], eligible: [true, false, true], x: 9, footprint: 10)
        precondition(accepted == 36 && heights == [2, 1, 2])
        let extra = SnowLanding.absorb(volume: 10, heights: &heights, limits: [2, 2, 2], eligible: [true, false, true], x: 9, footprint: 10)
        precondition(extra == 0)
        let flakeScene = SKScene(size: screen.size)
        let flakes = SnowDeposits(settlingDelay: 0)
        flakes.configure(enabled: true, automaticPlow: false, scene: flakeScene)
        flakes.update(ledges: [lower], screenFrame: screen, scene: flakeScene, amount: 0.5)
        var flakeVolume: CGFloat = 2
        precondition(flakes.catchFlake(from: CGPoint(x: 300, y: 450), to: CGPoint(x: 300, y: 350), size: 3, remainingVolume: &flakeVolume))
        precondition(flakeVolume < 0.001)
        let fullScene = SKScene(size: screen.size)
        let fullSnow = SnowDeposits(settlingDelay: 0)
        fullSnow.configure(enabled: true, automaticPlow: false, scene: fullScene)
        for _ in 0..<12 { fullSnow.update(ledges: [full], screenFrame: screen, scene: fullScene, amount: 0.5) }
        var bypassVolume: CGFloat = 2
        precondition(!fullSnow.catchFlake(from: CGPoint(x: 300, y: 450), to: CGPoint(x: 300, y: 350), size: 3, remainingVolume: &bypassVolume))
        precondition(bypassVolume == 2)
        print("14 vérifications réussies : réception sur fenêtre, surplus vers le bord suivant, bord plein, recouvrement et sol.")
    }
}
