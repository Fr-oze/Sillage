import AppKit
import SpriteKit

@main struct SideResizeChecks {
    static func main() {
        let screen = CGRect(x:0,y:0,width:1000,height:900)
        for replacedID in [false,true] {
        for left in [true,false] {
            let scene = SKScene(size:screen.size)
            let snow = SnowDeposits()
            snow.configure(enabled:true,automaticPlow:false,scene:scene,followWindows:true,hangDelay:0)
            let codex = SnowLedge(id:1,frame:CGRect(x:100,y:400,width:600,height:200),spans:[100...700],isDock:false,ownerPID:99)
            snow.step(at:0,scene:scene)
            snow.update(ledges:[codex],screenFrame:screen,scene:scene,amount:0.1)
            snow.step(at:3,scene:scene)
            for _ in 0..<12 { snow.update(ledges:[codex],screenFrame:screen,scene:scene,amount:0.1) }
            let roof = scene.children[1] as! SKShapeNode
            let newX:CGFloat = left ? 300:100
            let resized = SnowLedge(id:replacedID ? 3 : 1,frame:CGRect(x:newX,y:400,width:400,height:200),spans:[newX...(newX+400)],isDock:false,ownerPID:99)
            // WhatsApp vient d'être découvert : son délai initial ne doit pas bloquer la réception.
            let whatsapp = SnowLedge(id:2,frame:CGRect(x:50,y:100,width:850,height:200),spans:[50...900],isDock:false)
            snow.update(ledges:[resized,whatsapp],screenFrame:screen,scene:scene,amount:0,growthInterval:0.04)
            precondition(roof.path != nil && !roof.isHidden,"Le tas toujours soutenu doit rester sur Codex")
            precondition(roof.path!.boundingBoxOfPath.width > 350,"Ne pas vider toute la fenêtre")
            let slabs = scene.children.compactMap{$0 as? SKShapeNode}.filter{$0.zPosition == 4}
            precondition(!slabs.isEmpty)
            for slab in slabs {
                let bounds = slab.calculateAccumulatedFrame()
                if left { precondition(bounds.maxX < newX + 15,"Seul le bord gauche perd son appui") }
                else { precondition(bounds.minX > newX + 400 - 15,"Seul le bord droit perd son appui") }
            }
            let receiver = scene.children.compactMap{$0 as? SKShapeNode}.first{$0.zPosition == 2 && $0 !== roof}!
            precondition(receiver.path == nil)
            snow.step(at:5,scene:scene)
            precondition(receiver.path != nil,"WhatsApp doit recevoir la neige sans attendre trois secondes")
            precondition((scene.children[0] as! SKShapeNode).path == nil,"La plaque reçue ne doit pas aller au sol")
            precondition(roof.path != nil)
        }
        }
        print("Rétrécissement gauche et droit : tas conservé, seul le débord tombe, réception immédiate sur WhatsApp, sol inchangé.")
    }
}
