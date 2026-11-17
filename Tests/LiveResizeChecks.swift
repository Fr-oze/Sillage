import AppKit
import SpriteKit
@main struct LiveResizeChecks {
 static func main() {
  let screen = CGRect(x:0,y:0,width:1200,height:900)
  for left in [true,false] {
   let snow = SnowDeposits(settlingDelay:0,missingGrace:0.18)
   let scene = SKScene(size:screen.size)
   snow.configure(enabled:true,automaticPlow:false,scene:scene,followWindows:true,hangDelay:0.9)
   func ledge(_ i:Int, id:UInt32 = 1)->SnowLedge {
    let x:CGFloat = left ? 100+CGFloat(i)*5 : 100
    let width:CGFloat = 800-CGFloat(i)*5
    return SnowLedge(id:id,frame:CGRect(x:x,y:400,width:width,height:200),spans:[x...(x+width)],isDock:false,ownerPID:55)
   }
   snow.step(at:0,scene:scene)
   for _ in 0..<12 { snow.update(ledges:[ledge(0)],screenFrame:screen,scene:scene,amount:0.5) }
   let roof = scene.children[1] as! SKShapeNode
   for i in 1...60 {
    let t=Double(i)/30
    snow.step(at:t,scene:scene)
    snow.update(ledges:[ledge(i)],screenFrame:screen,scene:scene,amount:0,growthInterval:1.0/30)
    precondition(!roof.isHidden && roof.path != nil,"Ne jamais détacher le tas encore soutenu pendant 60 mesures")
    precondition(roof.path!.boundingBoxOfPath.width > 450)
   }
   // Omission transitoire, puis remplacement de l'identifiant natif.
   snow.update(ledges:[],screenFrame:screen,scene:scene,amount:0,growthInterval:0)
   precondition(roof.parent != nil && !roof.isHidden)
   snow.step(at:2.04,scene:scene)
   snow.update(ledges:[ledge(60,id:3)],screenFrame:screen,scene:scene,amount:0,growthInterval:0)
   precondition(roof.parent != nil && !roof.isHidden)
   let fragment = scene.children.compactMap{$0 as? SKShapeNode}.last{$0.zPosition == 4}!
   let y = fragment.position.y
   snow.step(at:2.08,scene:scene)
   precondition(fragment.position.y < y,"Le bord retiré tombe sans attente cartoon")
  }
  var polling=WindowPollSchedule()
  _=polling.shouldSample(at:0,pressed:false)
  var count=0
  for i in 1...300 { if polling.shouldSample(at:Double(i)/30,pressed:true) { count += 1 } }
  precondition(count==300,"Maintenir 30 Hz même quand le pointeur ne change pas")
  print("Resize continu gauche/droite, conservation du tas, omission transitoire, nouvel ID, chute sans délai et 30 Hz : OK")
 }
}
