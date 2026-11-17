import AppKit
import SpriteKit

@main
struct DepositLifecycleChecks {
    static func main() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let frame = CGRect(x: 100, y: 100, width: 600, height: 400)
        let scene = SKScene(size: screen.size)
        let deposits = SnowDeposits(settlingDelay: 0)
        deposits.configure(enabled: true, automaticPlow: false, scene: scene)
        deposits.step(at: 0, scene: scene)
        let exposed = SnowLedge(id: 42, frame: frame, spans: [100...700], isDock: false, ownerPID: 1)
        let covered = SnowLedge(id: 42, frame: frame, spans: [], isDock: false, ownerPID: 1)
        deposits.update(ledges: [exposed], screenFrame: screen, scene: scene, amount: 0.5)
        precondition(scene.children.count == 2)
        let roof = scene.children.last as! SKShapeNode
        precondition(!roof.isHidden && roof.path != nil)
        deposits.update(ledges: [covered], screenFrame: screen, scene: scene, amount: 0.5)
        precondition(roof.isHidden && roof.path == nil, "Une forme vide doit être masquée explicitement")
        precondition(scene.children.count == 2, "Recouvrir une fenêtre ne doit pas créer de plaques")
        deposits.update(ledges: [exposed], screenFrame: screen, scene: scene, amount: 0.5)
        precondition(!roof.isHidden && roof.path != nil)
        precondition(scene.children.last === roof, "Le dépôt doit rester attaché à son propriétaire")
        deposits.update(ledges: [], screenFrame: screen, scene: scene, amount: 0.5)
        precondition(roof.parent == nil)
        precondition(scene.children.count > 1)
        let fragment = scene.children.last!
        let suspendedY = fragment.position.y
        deposits.step(at: 0.5, scene: scene)
        precondition(fragment.position.y == suspendedY)
        // Un seul rendu tardif : la plaque doit déjà avoir rejoint le sol.
        deposits.step(at: 4, scene: scene)
        precondition(scene.children.count == 1, "Aucun reste en l'air après une chute")
        precondition((scene.children[0] as! SKShapeNode).path != nil)
        // Fermetures répétées : aucune file d'attente statique ni nœud orphelin.
        for i in 0..<40 {
            let ledge = SnowLedge(id: UInt32(i + 100), frame: frame, spans: [100...700], isDock: false)
            deposits.update(ledges: [ledge], screenFrame: screen, scene: scene, amount: 0.5)
        }
        deposits.update(ledges: [], screenFrame: screen, scene: scene, amount: 0.5)
        deposits.step(at: 13, scene: scene)
        precondition(scene.children.count == 1)
        deposits.update(ledges: [exposed], screenFrame: screen, scene: scene, amount: 0.5)
        let resized = SnowLedge(id: 42, frame: CGRect(x: 100, y: 100, width: 200, height: 400), spans: [100...300], isDock: false, ownerPID: 1)
        deposits.update(ledges: [resized], screenFrame: screen, scene: scene, amount: 0.5)
        deposits.step(at: 18, scene: scene)
        precondition(scene.children.count == 2, "Après rétrécissement, seuls le sol et le dépôt attaché restent")
        let attached = scene.children.first { $0 !== scene.children[0] }!
        let shifted = SnowLedge(id: 42, frame: resized.frame.offsetBy(dx: 100, dy: 80), spans: [200...400], isDock: false, ownerPID: 1)
        deposits.update(ledges: [shifted], screenFrame: screen, scene: scene, amount: 0.5)
        precondition(attached.position.x == 200 && attached.position.y == 578.5)
        precondition(attached.isHidden, "Un dépôt vidé ne doit pas laisser sa géométrie en cache")
        deposits.step(at: 23, scene: scene)
        precondition(scene.children.count == 2)
        deposits.update(ledges: [shifted], screenFrame: screen, scene: scene, amount: 0.5)
        deposits.update(ledges: [], screenFrame: screen, scene: scene, amount: 0.5)
        deposits.resetClock()
        deposits.step(at: 10000, scene: scene)
        precondition(scene.children.count > 1, "Le temps passé en pause ne compte pas comme une chute active")
        deposits.step(at: 10005, scene: scene)
        precondition(scene.children.count == 1)
        deposits.configure(enabled: false, automaticPlow: false, scene: scene)
        precondition(scene.children[0].isHidden)
        print("19 vérifications réussies : recouvrement, restauration, fermeture, rendu lent et absence de nœuds suspendus.")
    }
}
