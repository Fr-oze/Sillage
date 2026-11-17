import AppKit

@main
struct GeometryChecks {
    static func main() {
        let cg = CGRect(x: 100, y: 80, width: 500, height: 300)
        precondition(WindowGeometry.appKitRect(cg, primaryTop: 900) == CGRect(x: 100, y: 520, width: 500, height: 300))
        let frame = CGRect(x: 0, y: 0, width: 400, height: 200)
        precondition(WindowGeometry.exposedSpans(of: frame, inFront: []) == [0...400])
        precondition(WindowGeometry.exposedSpans(of: frame, inFront: [CGRect(x: 100, y: 150, width: 100, height: 100)]) == [0...100, 200...400])
        precondition(WindowGeometry.exposedSpans(of: frame, inFront: [CGRect(x: -10, y: 100, width: 420, height: 200)]).isEmpty)
        precondition(WindowGeometry.exposedSpans(of: frame, inFront: [CGRect(x: 0, y: 0, width: 400, height: 100)]) == [0...400])
        precondition(WindowGeometry.exposedSpans(of: frame, inFront: [CGRect(x: 50, y: 150, width: 100, height: 100), CGRect(x: 100, y: 180, width: 100, height: 100)]) == [0...50, 200...400])
        precondition(WindowGeometry.appKitRect(CGRect(x: -1200, y: -900, width: 800, height: 600), primaryTop: 900).minY == 1200)
        precondition(!WindowGeometry.isOccluder(layer: 20, isDock: false))
        precondition(WindowGeometry.isOccluder(layer: 0, isDock: false))
        precondition(WindowGeometry.isOccluder(layer: 20, isDock: true))
        precondition(WindowGeometry.windowListOptions.contains(.optionOnScreenOnly),
                     "Le calcul d'occultation exige une liste ordonnée d'avant en arrière")
        let chat = WindowGeometry.appKitRect(CGRect(x: 63, y: 124, width: 1338, height: 815), primaryTop: 1117)
        let finder = WindowGeometry.appKitRect(CGRect(x: 113, y: 521, width: 920, height: 436), primaryTop: 1117)
        let monitor = WindowGeometry.appKitRect(CGRect(x: 244, y: 420, width: 1059, height: 612), primaryTop: 1117)
        let browser = WindowGeometry.appKitRect(CGRect(x: 520, y: 283, width: 1162, height: 698), primaryTop: 1117)
        precondition(WindowGeometry.exposedSpans(of: finder, inFront: [chat]).isEmpty)
        precondition(WindowGeometry.exposedSpans(of: monitor, inFront: [chat]).isEmpty)
        precondition(WindowGeometry.exposedSpans(of: browser, inFront: [chat]) == [1401...1682])
        precondition(WindowGeometry.exposedSpans(of: chat, inFront: []).first == 63...1401)
        let usable = CGRect(x: 0, y: 75, width: 1728, height: 1009)
        precondition(WindowGeometry.headroom(above: CGRect(x: 1082, y: 543, width: 600, height: 600), visibleFrames: [usable]) == 0)
        precondition(WindowGeometry.headroom(above: chat, visibleFrames: [usable]) == 91)
        let fullScreen = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        let arcAuxiliary = CGRect(x: 1082, y: 543, width: 600, height: 600)
        precondition(!WindowGeometry.hasVisibleTop(arcAuxiliary, screenFrames: [fullScreen]))
        precondition(WindowGeometry.hasVisibleTop(fullScreen, screenFrames: [fullScreen]))
        precondition(WindowGeometry.hasVisibleTop(browser, screenFrames: [fullScreen]))
        let clampedArcAuxiliary = CGRect(x: 1082, y: 517, width: 600, height: 600)
        precondition(!WindowGeometry.hasVisibleTop(clampedArcAuxiliary, screenFrames: [usable]))
        precondition(WindowGeometry.hasVisibleTop(browser, screenFrames: [usable]))
        precondition(WindowGeometry.isFullscreen(fullScreen, screen: fullScreen))
        precondition(!WindowGeometry.isFullscreen(usable, screen: fullScreen), "Maximiser ne doit pas déneiger tout le bureau")
        precondition(!WindowGeometry.isFullscreen(fullScreen.insetBy(dx: 10, dy: 0), screen: fullScreen))
        print("25 vérifications réussies : coordonnées multi-écrans et occultation des bords.")
    }
}
