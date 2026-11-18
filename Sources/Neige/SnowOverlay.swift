import AppKit
import SpriteKit

final class SnowScene: SKScene {
    private var flakes: [(SKSpriteNode, CGFloat, CGFloat)] = []
    private var flakeVolumes: [CGFloat] = []
    private var lastTime: TimeInterval = 0
    private var sizeFactor: CGFloat = 1
    private var speedFactor: CGFloat = 1
    private var wind: CGFloat = 0
    private let deposits = SnowDeposits(missingGrace: 0.18)
    private var running = false
    private var season = Season.winter
    private var texture: SKTexture?
    private var trackingFast = false
    private let backgroundLayer = SKCropNode()
    private var lastOccluders: [CGRect]?

    func updateOcclusion(_ occluders: [CGRect], screenFrame: CGRect) {
        let local = occluders.map { $0.intersection(screenFrame) }.filter { !$0.isNull && !$0.isEmpty }
            .map { $0.offsetBy(dx: -screenFrame.minX, dy: -screenFrame.minY) }
        guard local != lastOccluders else { return }
        lastOccluders = local
        guard !local.isEmpty else { backgroundLayer.maskNode = nil; return }
        var visible = [CGRect(origin: .zero, size: size)]
        for cover in local {
            visible = visible.flatMap { rect -> [CGRect] in
                let cut = rect.intersection(cover)
                guard !cut.isNull && !cut.isEmpty else { return [rect] }
                return [
                    CGRect(x: rect.minX, y: rect.minY, width: cut.minX - rect.minX, height: rect.height),
                    CGRect(x: cut.maxX, y: rect.minY, width: rect.maxX - cut.maxX, height: rect.height),
                    CGRect(x: cut.minX, y: rect.minY, width: cut.width, height: cut.minY - rect.minY),
                    CGRect(x: cut.minX, y: cut.maxY, width: cut.width, height: rect.maxY - cut.maxY)
                ].filter { !$0.isEmpty }
            }
        }
        let mask = SKNode()
        // Keep an alpha-zero pixel even when no desktop is exposed.
        mask.addChild(SKSpriteNode(color: .clear, size: CGSize(width: 1, height: 1)))
        for rect in visible {
            let tile = SKSpriteNode(color: .white, size: rect.size)
            tile.anchorPoint = .zero
            tile.position = rect.origin
            mask.addChild(tile)
        }
        backgroundLayer.maskNode = mask
    }

    func setTrackingFast(_ fast: Bool) {
        trackingFast = fast
        updateFrameRate()
    }

    private func updateFrameRate() {
        let rate = trackingFast || deposits.cleaning ? 30 : 15
        if let view, view.preferredFramesPerSecond != rate { view.preferredFramesPerSecond = rate }
    }

    func updateLedges(_ ledges: [SnowLedge], screenFrame: CGRect, amount: Double, interval: TimeInterval, fullscreen: Bool) {
        deposits.update(ledges: ledges, screenFrame: screenFrame, scene: self, amount: amount, growthInterval: interval, fullscreen: fullscreen)
        deposits.step(at: ProcessInfo.processInfo.systemUptime, scene: self)
    }

    func setRunning(_ active: Bool) {
        if running != active {
            deposits.resetClock()
            lastTime = 0
            running = active
        }
    }

    func sendSnowplow() { deposits.requestPlow(); updateFrameRate() }

    func apply(_ settings: Settings) {
        deposits.backgroundLayer = backgroundLayer
        deposits.configure(enabled: !settings.behindWindows, automaticPlow: settings.automaticPlow, scene: self, followWindows: true, hangDelay: settings.cartoonPause ? SnowSurfaceMath.hangTime : 0)
        if season != settings.season || texture == nil {
            season = settings.season
            deposits.setSeason(season)
            texture = season.particleTexture()
        }
        let colors = season.colors
        let previousSizeFactor = sizeFactor
        sizeFactor = CGFloat(settings.size)
        for i in flakeVolumes.indices { flakeVolumes[i] *= sizeFactor / previousSizeFactor }
        speedFactor = CGFloat(settings.speed)
        wind = CGFloat(settings.wind)
        let density = season == .autumn ? 0.55 : 1.0
        let visible = Int(Double(flakes.count) * settings.amount * density)
        for (i, flake) in flakes.enumerated() {
            flake.0.isHidden = i >= visible
            flake.0.texture = texture
            flake.0.color = colors[i % colors.count]
            flake.0.colorBlendFactor = season == .winter ? 0 : 1
            let scale: CGFloat = season == .autumn ? 1.8 : season == .spring ? 1.6 : season == .summer ? 0.8 : 1
            flake.0.setScale(sizeFactor * scale)
            if season == .autumn { flake.0.xScale *= 0.75 }
            if season == .winter || season == .summer { flake.0.zRotation = 0 }
        }
    }

    override func didMove(to view: SKView) {
        guard flakes.isEmpty else { return }
        backgroundColor = .clear
        addChild(backgroundLayer)
        deposits.backgroundLayer = backgroundLayer
        let texture = season.particleTexture()
        // Un plafond global réparti entre les écrans, sans moteur physique.
        let count = max(12, 220 / max(1, NSScreen.screens.count))
        for _ in 0..<count {
            let side = CGFloat.random(in: 2...5)
            let node = SKSpriteNode(texture: texture, size: CGSize(width: side, height: side))
            node.position = CGPoint(x: .random(in: 0...size.width), y: .random(in: 0...size.height))
            node.alpha = .random(in: 0.35...0.85)
            backgroundLayer.addChild(node)
            flakeVolumes.append(max(0.3, side * 0.6))
            flakes.append((node, .random(in: 25...65), .random(in: -7...12)))
        }
    }

    override func update(_ currentTime: TimeInterval) {
        let dt = CGFloat(lastTime == 0 ? 0 : min(0.1, currentTime - lastTime))
        lastTime = currentTime
        deposits.step(at: ProcessInfo.processInfo.systemUptime, scene: self)
        updateFrameRate()
        for index in flakes.indices where !flakes[index].0.isHidden {
            let (node, speed, drift) = flakes[index]
            let previous = node.position
            if season == .autumn || season == .spring { node.zRotation += dt * (drift * 0.14) }
            node.position.y -= speed * speedFactor * dt
            node.position.x += (drift + wind) * dt
            if deposits.catchFlake(from: previous, to: node.position, size: node.size.width * sizeFactor, remainingVolume: &flakeVolumes[index]) {
                node.position.y = size.height + 8
                node.position.x = .random(in: 0...size.width)
                flakeVolumes[index] = max(0.3, node.size.width * sizeFactor * 0.6)
            } else if node.position.y < -8 {
                deposits.flakeReachedGround(x: node.position.x, size: node.size.width * sizeFactor, volume: flakeVolumes[index])
                node.position.y = size.height + 8
                node.position.x = .random(in: 0...size.width)
                flakeVolumes[index] = max(0.3, node.size.width * sizeFactor * 0.6)
            }
            if node.position.x < -8 { node.position.x = size.width + 8 }
            if node.position.x > size.width + 8 { node.position.x = -8 }
        }
    }
}

@MainActor
final class SnowOverlay: NSObject {
    private var windows: [NSWindow] = []
    private var views: [SKView] = []
    private var screenFrames: [CGRect] = []
    private var timer: Timer?
    private var settings: Settings?
    private var isActive = false
    private var polling = WindowPollSchedule()
    private var lastSample: TimeInterval = 0
    private var lastLedges: [SnowLedge] = []
    private var framesPerSecond = 15

    override init() {
        super.init()
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification] {
            NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(wakeTracking), name: name, object: nil)
        }
    }

    @objc private func wakeTracking() {
        polling.requestFast(at: ProcessInfo.processInfo.systemUptime)
        sampleWindows()
    }

    func rebuild(active: Bool) {
        if screenFrames == NSScreen.screens.map(\.frame), !windows.isEmpty {
            polling.requestFast(at: ProcessInfo.processInfo.systemUptime)
            setActive(active)
            return
        }
        timer?.invalidate()
        timer = nil
        windows.forEach { $0.orderOut(nil) }
        views.forEach { $0.isPaused = true; $0.presentScene(nil) }
        windows.removeAll()
        views.removeAll()
        screenFrames.removeAll()
        for screen in NSScreen.screens {
            let window = NSWindow(contentRect: screen.frame, styleMask: .borderless,
                                  backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) - 1)
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            window.hidesOnDeactivate = false
            let view = SKView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.allowsTransparency = true
            view.preferredFramesPerSecond = framesPerSecond
            view.ignoresSiblingOrder = true
            let scene = SnowScene(size: screen.frame.size)
            scene.scaleMode = .resizeFill
            view.presentScene(scene)
            window.contentView = view
            windows.append(window)
            views.append(view)
            screenFrames.append(screen.frame)
        }
        setActive(active)
    }

    func apply(_ settings: Settings) {
        self.settings = settings
        for view in views { (view.scene as? SnowScene)?.apply(settings) }
        polling.requestFast(at: ProcessInfo.processInfo.systemUptime)
        sampleWindows()
    }

    func sendSnowplow() {
        for view in views { (view.scene as? SnowScene)?.sendSnowplow() }
    }

    func setActive(_ active: Bool) {
        isActive = active
        for view in views {
            (view.scene as? SnowScene)?.setRunning(active)
            view.isPaused = !active
        }
        configureTimer()
        for window in windows {
            if active { window.orderFrontRegardless() } else { window.orderOut(nil) }
        }
    }

    private func configureTimer() {
        let shouldRun = isActive && settings != nil
        if shouldRun && timer == nil {
            let timer = Timer(timeInterval: 1.0 / 30.0, target: self, selector: #selector(sampleWindows), userInfo: nil, repeats: true)
            timer.tolerance = 0.001
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
            sampleWindows()
        } else if !shouldRun {
            timer?.invalidate()
            timer = nil
            updateFrameRate(fast: false)
            if isActive, let settings { updateScenes([], amount: settings.amount) }
        }
    }

    private func updateFrameRate(fast: Bool) {
        let rate = fast ? 30 : 15
        guard rate != framesPerSecond else { return }
        framesPerSecond = rate
        for view in views { (view.scene as? SnowScene)?.setTrackingFast(fast) }
    }

    @objc private func sampleWindows() {
        guard isActive, timer != nil, let settings else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let pressed = CGEventSource.buttonState(.combinedSessionState, button: .left)
        let shouldSample = polling.shouldSample(at: now, pressed: pressed)
        defer { updateFrameRate(fast: polling.isFast(at: now)) }
        guard shouldSample else { return }
        let interval = lastSample == 0 ? 0 : min(1, now - lastSample)
        lastSample = now
        let ledges = WindowGeometry.visibleLedges(windows: !settings.behindWindows && settings.accumulateWindows, dock: !settings.behindWindows && settings.accumulateDock)
        if settings.dockEstimated != WindowGeometry.dockIsEstimated {
            settings.dockEstimated = WindowGeometry.dockIsEstimated
        }
        if ledges.count != lastLedges.count || zip(ledges, lastLedges).contains(where: { $0.id != $1.id || $0.frame != $1.frame || $0.spans != $1.spans }) { polling.noteGeometryChange(at: now) }
        lastLedges = ledges
        updateScenes(ledges, amount: settings.amount, interval: interval)
    }

    private func updateScenes(_ ledges: [SnowLedge], amount: Double, interval: TimeInterval = 0) {
        for (index, view) in views.enumerated() {
            guard let scene = view.scene as? SnowScene else { continue }
            let frame = screenFrames[index]
            let foreground = WindowGeometry.fullscreenForeground.first { $0.frame == frame }?.ids
            let supports = foreground.map { ids in ledges.filter { ids.contains($0.id) || $0.isDock } } ?? ledges
            scene.updateOcclusion(WindowGeometry.particleOccluders, screenFrame: frame)
            scene.updateLedges(supports, screenFrame: frame, amount: amount, interval: interval, fullscreen: foreground != nil && supports.isEmpty)
        }
    }

}
