import AppKit
import SpriteKit

@main
struct StabilityChecks {
    static func main() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let initial = SnowLedge(id: 1, frame: CGRect(x: 100, y: 100, width: 600, height: 400), spans: [100...700], isDock: false)
        let scene = SKScene(size: screen.size)
        let snow = SnowDeposits()
        snow.configure(enabled: true, automaticPlow: false, scene: scene)
        snow.step(at: 0, scene: scene)
        snow.update(ledges: [initial], screenFrame: screen, scene: scene, amount: 0.5)
        let roof = scene.children[1] as! SKShapeNode
        precondition(roof.isHidden && roof.path == nil)
        var volume: CGFloat = 2
        precondition(!snow.catchFlake(from: CGPoint(x: 300, y: 550), to: CGPoint(x: 300, y: 450), size: 3, remainingVolume: &volume))
        precondition(volume == 2)
        snow.step(at: 2.9, scene: scene)
        snow.update(ledges: [initial], screenFrame: screen, scene: scene, amount: 0.5)
        precondition(roof.isHidden)
        snow.step(at: 3, scene: scene)
        snow.update(ledges: [initial], screenFrame: screen, scene: scene, amount: 0.5)
        precondition(!roof.isHidden && roof.path != nil)
        let moved = SnowLedge(id: 1, frame: initial.frame.offsetBy(dx: 60, dy: 0), spans: [160...760], isDock: false)
        snow.step(at: 3.1, scene: scene)
        snow.update(ledges: [moved], screenFrame: screen, scene: scene, amount: 0.5)
        precondition(roof.isHidden)
        snow.step(at: 5.9, scene: scene)
        snow.update(ledges: [moved], screenFrame: screen, scene: scene, amount: 0.5)
        precondition(roof.isHidden)
        let resized = SnowLedge(id: 1, frame: CGRect(x: 160, y: 100, width: 400, height: 400), spans: [160...560], isDock: false)
        snow.update(ledges: [resized], screenFrame: screen, scene: scene, amount: 0.5)
        snow.step(at: 8.8, scene: scene)
        snow.update(ledges: [resized], screenFrame: screen, scene: scene, amount: 0.5)
        precondition(roof.isHidden)
        snow.step(at: 9, scene: scene)
        snow.update(ledges: [resized], screenFrame: screen, scene: scene, amount: 0.5)
        precondition(!roof.isHidden)
        let covered = SnowLedge(id: 1, frame: resized.frame, spans: [], isDock: false)
        snow.update(ledges: [covered], screenFrame: screen, scene: scene, amount: 0.5)
        snow.update(ledges: [resized], screenFrame: screen, scene: scene, amount: 0.5)
        precondition(!roof.isHidden, "Changer le premier plan ne doit pas relancer le délai de stabilité")
        precondition(!SnowSurfaceMath.supportChanged(from: initial.frame, to: initial.frame.offsetBy(dx: 0.5, dy: 0)))
        precondition(SnowSurfaceMath.supportChanged(from: initial.frame, to: resized.frame))
        let rapidScene = SKScene(size: screen.size)
        let rapidSnow = SnowDeposits()
        rapidSnow.configure(enabled: true, automaticPlow: false, scene: rapidScene)
        rapidSnow.step(at: 0, scene: rapidScene)
        var latest = initial
        for i in 0...36 {
            rapidSnow.step(at: Double(i) * 0.1, scene: rapidScene)
            latest = SnowLedge(id: 1, frame: initial.frame.offsetBy(dx: CGFloat(i) * 4, dy: 0), spans: [(100 + CGFloat(i) * 4)...(700 + CGFloat(i) * 4)], isDock: false)
            rapidSnow.update(ledges: [latest], screenFrame: screen, scene: rapidScene, amount: 0.5)
            precondition(rapidScene.children.count == 2 && rapidScene.children[1].isHidden,
                         "Des déplacements répétés ne doivent pas produire de nouveaux tas ni de plaques")
        }
        rapidSnow.step(at: 6.5, scene: rapidScene)
        rapidSnow.update(ledges: [latest], screenFrame: screen, scene: rapidScene, amount: 0.5)
        precondition(rapidScene.children[1].isHidden)
        rapidSnow.step(at: 6.7, scene: rapidScene)
        rapidSnow.update(ledges: [latest], screenFrame: screen, scene: rapidScene, amount: 0.5)
        precondition(!rapidScene.children[1].isHidden)
        print("15 vérifications réussies : délai initial, mouvement, redimensionnement et recouvrement.")
    }
}
