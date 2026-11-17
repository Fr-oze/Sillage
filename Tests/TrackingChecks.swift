import AppKit
import SpriteKit

@main struct TrackingChecks {
    static func main() {
        var schedule = WindowPollSchedule()
        precondition(schedule.shouldSample(at: 0, pressed: false))
        precondition(!schedule.shouldSample(at: 0.5, pressed: false))
        precondition(schedule.shouldSample(at: 1, pressed: false))
        precondition(schedule.shouldSample(at: 1.04, pressed: true))
        precondition(!schedule.shouldSample(at: 1.06, pressed: true))
        precondition(schedule.shouldSample(at: 1.08, pressed: true))
        precondition(schedule.shouldSample(at: 1.12, pressed: false))
        precondition(!schedule.shouldSample(at: 1.7, pressed: false))
        precondition(schedule.shouldSample(at: 2.12, pressed: false))
        let rect = CGRect(x:0,y:0,width:1000,height:900)
        let ledge = SnowLedge(id:1,frame:CGRect(x:100,y:300,width:600,height:200),spans:[100...700],isDock:false)
        let scene = SKScene(size:rect.size)
        let snow = SnowDeposits(settlingDelay:0)
        snow.configure(enabled:true,automaticPlow:false,scene:scene,followWindows:true,hangDelay:0)
        snow.step(at:0,scene:scene)
        for _ in 0..<12 { snow.update(ledges:[ledge],screenFrame:rect,scene:scene,amount:0.5) }
        let roof = scene.children[1] as! SKShapeNode
        let before = roof.path!.boundingBoxOfPath
        let moved = SnowLedge(id:1,frame:ledge.frame.offsetBy(dx:100,dy:30),spans:[200...800],isDock:false)
        snow.update(ledges:[moved],screenFrame:rect,scene:scene,amount:0,growthInterval:0.04)
        precondition(scene.children.count == 2 && roof.path!.boundingBoxOfPath == before)
        precondition(roof.position.x == 200 && abs(roof.position.y - 528.5) < 0.01)
        snow.update(ledges:[moved],screenFrame:rect,scene:scene,amount:0,fullscreen:true)
        precondition(roof.parent == nil && scene.children.count > 1)
        snow.step(at:4,scene:scene)
        precondition(scene.children.count == 1 && (scene.children[0] as! SKShapeNode).path != nil)
        snow.update(ledges:[moved],screenFrame:rect,scene:scene,amount:1,fullscreen:true)
        precondition(scene.children.count == 1)
        let polygon = [CGPoint(x:0,y:0),CGPoint(x:100,y:0),CGPoint(x:100,y:10),CGPoint(x:0,y:10)]
        let cut = SnowContour.clip(polygon,left:40,right:70)
        let remains = SnowContour.removingBottomArea([cut],area:100)
        precondition(abs(remains.reduce(0){$0+SnowContour.area($1)} - 200) < 0.001)
        precondition(SnowContour.bounds(remains).minY > 3.3)
        precondition(SnowSweep.crossing(from:CGPoint(x:0,y:600),to:CGPoint(x:0,y:100),plane:400) == 0.4)
        print("17 vérifications réussies : suivi 30 Hz/repos, conservation du tas en mouvement, plein écran, découpe partielle et collision continue.")
    }
}
