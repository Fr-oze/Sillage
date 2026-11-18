import AppKit
import SpriteKit

// Plaques vectorielles, sans moteur physique ni file de suspension indéfinie.
final class SnowDeposits {
    private final class Surface {
        var id: CGWindowID
        var isDock: Bool
        var maxSnowHeight: CGFloat
        let ownerPID: pid_t
        var frame: CGRect
        var spans: [ClosedRange<CGFloat>]
        var missingSince: TimeInterval?
        var growthPending: CGFloat = 0
        var readyAt: TimeInterval
        var heights: [CGFloat]
        var renderedPolygons: [[CGPoint]] = []
        let node = SKShapeNode()
        init(ledge: SnowLedge, readyAt: TimeInterval) {
            self.readyAt = readyAt
            id = ledge.id
            isDock = ledge.isDock
            maxSnowHeight = ledge.maxSnowHeight
            ownerPID = ledge.ownerPID
            frame = ledge.frame
            spans = ledge.spans
            heights = Array(repeating: 0, count: max(2, Int(ceil(frame.width / 18))))
            node.fillColor = NSColor(calibratedRed: 0.97, green: 0.985, blue: 1, alpha: 1)
            node.strokeColor = NSColor(calibratedRed: 0.72, green: 0.82, blue: 0.92, alpha: 0.3)
            node.lineWidth = 0.5
            node.zPosition = 2
        }
        func isExposed(at localX: CGFloat) -> Bool {
            let globalX = frame.minX + localX
            return SnowSurfaceMath.supports(localX: localX, width: frame.width)
                && spans.contains { $0.contains(globalX) }
        }
    }
    private struct Fragment {
        let sourceID: CGWindowID
        let node: SKShapeNode
        var motion: SnowFallMotion
        var polygons: [[CGPoint]]
        var volume: CGFloat
        let initialVolume: CGFloat
        let footprint: CGFloat
    }
    private var surfaces: [CGWindowID: Surface] = [:]
    private var fragments: [Fragment] = []
    private var receivers: [Surface] = []
    private var dirtySurfaces: Set<CGWindowID> = []
    private var redrawTime: CGFloat = 0
    private var lastClock: TimeInterval?
    private var simulationTime: TimeInterval = 0
    private var ground: GroundSnow?
    weak var backgroundLayer: SKNode?
    private let groundNode = SKShapeNode()
    private var groundDirty = false
    private var groundDrawTime: CGFloat = 0
    private var plow: SKNode?
    private var plowPile: SKShapeNode?
    private var sweptUntil: CGFloat = -100
    private var pushedVolume: CGFloat = 0
    private var plowCooldown: CGFloat = 0
    private var automaticPlow = true
    private var enabled = true
    private var requestedPlow = false
    private var season = Season.winter
    var cleaning: Bool { enabled && (requestedPlow || plow != nil) }

    func setSeason(_ season: Season) {
        guard self.season != season else { return }
        reset()
        self.season = season
        groundNode.fillColor = season.depositColor
        plowCooldown = 0
    }
    private var fullscreenActive = false
    private var followsWindows = false
    private var hangDelay = SnowSurfaceMath.hangTime
    private let missingGrace: TimeInterval
    private let settlingDelay: TimeInterval

    init(settlingDelay: TimeInterval = 3, missingGrace: TimeInterval = 0) {
        self.missingGrace = max(0, missingGrace)
        self.settlingDelay = max(0, settlingDelay)
    }

    func configure(enabled: Bool, automaticPlow: Bool, scene: SKScene, followWindows: Bool = false, hangDelay: CGFloat = SnowSurfaceMath.hangTime) {
        self.automaticPlow = automaticPlow
        self.followsWindows = followWindows
        self.hangDelay = hangDelay
        if self.enabled && !enabled { reset() }
        self.enabled = enabled
        if ground == nil {
            ground = GroundSnow(width: scene.size.width)
            groundNode.fillColor = season.depositColor
            groundNode.strokeColor = .clear
            groundNode.zPosition = 3
            (backgroundLayer ?? scene).addChild(groundNode)
        }
        groundNode.isHidden = !enabled
    }

    func resetClock() { lastClock = nil }

    func requestPlow() { requestedPlow = true }

    func update(ledges: [SnowLedge], screenFrame: CGRect, scene: SKScene, amount: Double, growthInterval: TimeInterval = 1, fullscreen: Bool = false) {
        guard enabled else { return }
        if fullscreen {
            if !fullscreenActive {
                SnowDiagnostics.record("Plein écran : détachement des tas")
                receivers.removeAll()
                for surface in surfaces.values {
                    release(surface: surface, scene: scene, delayOverride: 0)
                    surface.node.removeFromParent()
                }
                surfaces.removeAll()
                dirtySurfaces.removeAll()
                for i in fragments.indices {
                    let old = fragments[i].motion
                    fragments[i].motion = SnowFallMotion(origin: fragments[i].node.position, vx: old.vx,
                        spin: old.spin, bornAt: simulationTime, delay: 0)
                }
            }
            fullscreenActive = true
            return
        }
        fullscreenActive = false
        let relevant = ledges.filter {
            $0.frame.maxY > screenFrame.minY && $0.frame.maxY < screenFrame.maxY
                && $0.frame.maxX > screenFrame.minX && $0.frame.minX < screenFrame.maxX
        }
        let liveIDs = Set(relevant.map(\.id))
        // Certaines apps remplacent leur fenêtre native durant un resize.
        // Réassocier seulement un support disparu du même processus et même bord.
        for ledge in relevant where surfaces[ledge.id] == nil && ledge.ownerPID > 0 {
            let matches = surfaces.values.filter { old in
                !liveIDs.contains(old.id) && old.ownerPID == ledge.ownerPID
                    && SnowSurfaceMath.sameResizingSupport(old.frame, ledge.frame)
            }
            if matches.count == 1, let old = matches.first {
                surfaces.removeValue(forKey: old.id)
                SnowDiagnostics.record("Support réassocié \(old.id) → \(ledge.id)")
                old.id = ledge.id
                surfaces[ledge.id] = old
            }
        }

        for id in Array(surfaces.keys) where !liveIDs.contains(id) {
            guard let surface = surfaces[id] else { continue }
            if surface.missingSince == nil { surface.missingSince = simulationTime }
            // Ne pas transformer une omission transitoire de CGWindowList en fermeture.
            guard simulationTime - (surface.missingSince ?? simulationTime) >= missingGrace else { continue }
            surfaces.removeValue(forKey: id)
            SnowDiagnostics.record("Support absent id=\(id), rect=\(surface.frame)")
            release(surface: surface, scene: scene)
            surface.node.removeFromParent()
        }
        for ledge in relevant {
            if let old = surfaces[ledge.id], old.ownerPID != ledge.ownerPID {
                release(surface: old, scene: scene)
                old.node.removeFromParent()
                surfaces.removeValue(forKey: ledge.id)
            }
            let surface: Surface
            var moved = false
            var geometryChanged = true
            if let existing = surfaces[ledge.id] {
                surface = existing
                surface.missingSince = nil
                geometryChanged = surface.frame != ledge.frame || surface.spans != ledge.spans
                if SnowSurfaceMath.supportChanged(from: surface.frame, to: ledge.frame) {
                    surface.readyAt = simulationTime + settlingDelay
                }
                let shed = SnowSurfaceMath.shedFraction(from: surface.frame, to: ledge.frame)
                moved = shed > 0
                // Pendant un redimensionnement, préserver la neige en coordonnées écran.
                // Un déplacement pur transporte au contraire tout le tas avec la fenêtre.
                let resizing = abs(surface.frame.width - ledge.frame.width) > 0.01
                let offset = resizing ? ledge.frame.minX - surface.frame.minX : 0
                if moved && !followsWindows { release(surface: surface, scene: scene) }
                let oldHeights = surface.heights
                let newCount = max(2, Int(ceil(ledge.frame.width / 18)))
                if resizing {
                    release(surface: surface, scene: scene,
                        keeping: (offset + SnowSurfaceMath.cornerInset)...(offset + max(SnowSurfaceMath.cornerInset, ledge.frame.width - SnowSurfaceMath.cornerInset)), delayOverride: 0)
                    surface.heights = (0..<newCount).map { i in
                        let x = (CGFloat(i) + 0.5) * 18 + offset
                        guard x >= 0 && x < surface.frame.width else { return 0 }
                        return SnowContour.height(at: x, heights: oldHeights)
                    }
                }
                surface.frame = ledge.frame
                surface.spans = ledge.spans
                surface.isDock = ledge.isDock
                surface.maxSnowHeight = ledge.maxSnowHeight
            } else {
                surface = Surface(ledge: ledge, readyAt: simulationTime + settlingDelay)
                surface.node.fillColor = season.depositColor
                surfaces[ledge.id] = surface
                scene.addChild(surface.node)
            }
            let position = CGPoint(x: ledge.frame.minX - screenFrame.minX,
                                   y: ledge.frame.maxY - screenFrame.minY - SnowSurfaceMath.contactOverlap)
            // Le dépôt restant suit la fenêtre entre deux mesures, sans aucun fondu.
            surface.node.removeAllActions()
            surface.node.position = position
            surface.growthPending += CGFloat(max(0, min(1, growthInterval)))
            let growth = surface.growthPending >= 0.24 ? surface.growthPending : 0
            if growth > 0 { surface.growthPending = 0 }
            for i in surface.heights.indices where surface.isExposed(at: (CGFloat(i) + 0.5) * 18) && !moved && simulationTime >= surface.readyAt {
                let x = (CGFloat(i) + 0.5) * 18
                let ceiling = SnowContour.capacity(x: x, seed: ledge.id, dock: ledge.isDock)
                let remaining = max(0, 1 - surface.heights[i] / ceiling)
                surface.heights[i] = min(ceiling, surface.heights[i] + CGFloat(amount) * 0.7 * (0.12 + remaining) * growth)
            }
            if geometryChanged || growth > 0 || dirtySurfaces.contains(surface.id) { redraw(surface) }
        }
        receivers = surfaces.values.filter { $0.missingSince == nil }.sorted { $0.node.position.y > $1.node.position.y }
        dirtySurfaces.removeAll()
    }

    private func redraw(_ surface: Surface) {
        let visibleHeights = surface.heights.map { min($0, surface.maxSnowHeight) }
        let wholeContour = SnowContour.polygons(width: surface.frame.width, heights: visibleHeights,
            spans: [0...surface.frame.width])
        surface.renderedPolygons = SnowContour.visiblePolygons(wholeContour,
            spans: surface.spans.map { ($0.lowerBound - surface.frame.minX)...($0.upperBound - surface.frame.minX) })
        drawSurface(surface)

    }

    private func release(surface: Surface, scene: SKScene, keeping: ClosedRange<CGFloat>? = nil, delayOverride: CGFloat? = nil) {
        let selected: [[CGPoint]]
        if let kept = keeping {
            selected = surface.renderedPolygons.flatMap {
                [SnowContour.clip($0, left: -100000, right: kept.lowerBound),
                 SnowContour.clip($0, left: kept.upperBound, right: 100000)]
            }.filter { SnowContour.area($0) > 0.1 }
            surface.renderedPolygons = surface.renderedPolygons.map {
                SnowContour.clip($0, left: kept.lowerBound, right: kept.upperBound)
            }.filter { SnowContour.area($0) > 0.1 }
        } else {
            selected = surface.renderedPolygons
            surface.renderedPolygons = []
            surface.heights = Array(repeating: 0, count: surface.heights.count)
        }
        drawSurface(surface)
        guard let left = selected.flatMap({ $0 }).map(\.x).min(),
              let right = selected.flatMap({ $0 }).map(\.x).max(), right > left else { return }
        SnowDiagnostics.record("Détachement id=\(surface.id) x=\(left)...\(right) appui=\(surface.frame) découpe=\(String(describing: keeping))")
        // Quelques grandes plaques, découpées dans le contour affiché, pas des capsules.
        let available = max(1, 120 - fragments.count)
        let pieces = min(available, min(5, max(1, Int(ceil((right - left) / 200)))))
        for index in 0..<pieces {
            let a = left + (right - left) * CGFloat(index) / CGFloat(pieces)
            let b = left + (right - left) * CGFloat(index + 1) / CGFloat(pieces)
            let polygons = selected.map { SnowContour.clip($0, left: a, right: b) }
                .filter { SnowContour.area($0) > 0.1 }
            let volume = polygons.reduce(CGFloat(0)) { $0 + SnowContour.area($1) }
            guard volume > 0.1 else { continue }
            let center = CGPoint(x: (a + b) / 2, y: 0)
            let node = SKShapeNode(path: SnowContour.path(polygons, offset: CGPoint(x: -center.x, y: 0)))
            node.fillColor = surface.node.fillColor
            node.strokeColor = .clear
            node.position = CGPoint(x: surface.node.position.x + center.x, y: surface.node.position.y)
            node.zPosition = 4
            scene.addChild(node)
            let motion = SnowFallMotion(origin: node.position, vx: .random(in: -5...5),
                spin: .random(in: -0.13...0.13), bornAt: simulationTime,
                delay: TimeInterval((delayOverride ?? hangDelay) + (delayOverride == 0 ? 0 : CGFloat(index) * 0.035)))
            fragments.append(Fragment(sourceID: surface.id, node: node, motion: motion, polygons: polygons.map { $0.map { CGPoint(x: $0.x - center.x, y: $0.y) } }, volume: volume, initialVolume: volume, footprint: b - a))
        }
    }

    func flakeReachedGround(x: CGFloat, size: CGFloat, volume: CGFloat? = nil) {
        guard enabled else { return }
        ground?.add(volume: volume ?? max(0.3, size * 0.6), x: x)
        groundDirty = true
    }

    private func impactPlane(_ surface: Surface, x: CGFloat, footprint: CGFloat, fallingSlab: Bool = false) -> CGFloat? {
        guard fallingSlab || simulationTime >= surface.readyAt else { return nil }
        let localX = x - surface.node.position.x
        let radius = max(2, footprint / 2)
        guard localX + radius >= SnowSurfaceMath.cornerInset,
              localX - radius <= surface.frame.width - SnowSurfaceMath.cornerInset else { return nil }
        let visible = surface.spans.contains { span in
            let left = max(SnowSurfaceMath.cornerInset, span.lowerBound - surface.frame.minX)
            let right = min(surface.frame.width - SnowSurfaceMath.cornerInset, span.upperBound - surface.frame.minX)
            return localX + radius > left && localX - radius < right
        }
        guard visible else { return nil }
        let sampleX = min(surface.frame.width - SnowSurfaceMath.cornerInset, max(SnowSurfaceMath.cornerInset, localX))
        return surface.node.position.y + min(surface.maxSnowHeight, SnowContour.height(at: sampleX, heights: surface.heights))
    }

    private func coverage(_ surface: Surface, x: CGFloat, footprint: CGFloat) -> CGFloat {
        let half = max(1, footprint / 2)
        let left = x - half, right = x + half
        let covered = surface.spans.reduce(CGFloat(0)) { total, span in
            let a = surface.node.position.x + max(SnowSurfaceMath.cornerInset, span.lowerBound - surface.frame.minX)
            let b = surface.node.position.x + min(surface.frame.width - SnowSurfaceMath.cornerInset, span.upperBound - surface.frame.minX)
            return total + max(0, min(right, b) - max(left, a))
        }
        return min(1, covered / (2 * half))
    }

    private func absorb(_ volume: CGFloat, x: CGFloat, footprint: CGFloat, on surface: Surface, fallingSlab: Bool = false) -> CGFloat {
        guard fallingSlab || simulationTime >= surface.readyAt else { return 0 }
        let limits = surface.heights.indices.map {
            min(surface.maxSnowHeight, SnowContour.capacity(x: (CGFloat($0) + 0.5) * 18, seed: surface.id, dock: surface.isDock))
        }
        let eligible = surface.heights.indices.map { surface.isExposed(at: (CGFloat($0) + 0.5) * 18) }
        let accepted = SnowLanding.absorb(volume: volume, heights: &surface.heights, limits: limits,
            eligible: eligible, x: x - surface.node.position.x, footprint: footprint)
        if accepted > 0.001 { dirtySurfaces.insert(surface.id) }
        return accepted
    }

    func catchFlake(from old: CGPoint, to new: CGPoint, size: CGFloat, remainingVolume: inout CGFloat) -> Bool {
        guard enabled, new.y < old.y else { return false }
        for surface in receivers {
            let base = surface.node.position.y
            guard base < old.y else { continue }
            // Receivers are ordered by height, but their snow caps may differ.
            guard base + surface.maxSnowHeight >= new.y else { continue }
            guard let plane = impactPlane(surface, x: new.x, footprint: size), plane < old.y, plane >= new.y else { continue }
            let intercepted = remainingVolume * coverage(surface, x: new.x, footprint: size)
            remainingVolume -= absorb(intercepted, x: new.x, footprint: size, on: surface)
            if remainingVolume <= 0.001 { return true }
        }
        return false
    }

    private func receive(_ fragment: inout Fragment, on surface: Surface, position: CGPoint, angle: CGFloat) {
        var world = SnowContour.transformed(fragment.polygons, position: position, angle: angle)
        for span in surface.spans {
            let left = surface.node.position.x + max(SnowSurfaceMath.cornerInset, span.lowerBound - surface.frame.minX)
            let right = surface.node.position.x + min(surface.frame.width - SnowSurfaceMath.cornerInset, span.upperBound - surface.frame.minX)
            guard right > left else { continue }
            let candidates = world.map { SnowContour.clip($0, left: left, right: right) }.filter { SnowContour.area($0) > 0.001 }
            let mass = candidates.reduce(CGFloat(0)) { $0 + SnowContour.area($1) }
            guard mass > 0.001 else { continue }
            let bounds = SnowContour.bounds(candidates)
            let accepted = absorb(mass, x: bounds.midX, footprint: bounds.width, on: surface, fallingSlab: true)
            guard accepted > 0.001 else {
                SnowDiagnostics.record("Réception impossible id=\(surface.id) : bord saturé, volume=\(mass)")
                continue
            }
            SnowDiagnostics.record("Réception id=\(surface.id) volume=\(accepted)/\(mass)")
            let outside = world.flatMap { polygon in
                [SnowContour.clip(polygon, left: -100000, right: left), SnowContour.clip(polygon, left: right, right: 100000)]
            }.filter { SnowContour.area($0) > 0.001 }
            world = outside + SnowContour.removingBottomArea(candidates, area: accepted)
        }
        fragment.polygons = SnowContour.transformed(world, position: position, angle: angle, inverse: true)
        fragment.volume = fragment.polygons.reduce(CGFloat(0)) { $0 + SnowContour.area($1) }
        fragment.node.path = fragment.polygons.isEmpty ? nil : SnowContour.path(fragment.polygons)
    }

    private func drawSurface(_ surface: Surface) {
        if surface.renderedPolygons.isEmpty {
            surface.node.isHidden = true
            surface.node.path = nil
        } else {
            surface.node.path = SnowContour.path(surface.renderedPolygons)
            surface.node.isHidden = false
        }
    }

    func step(at now: TimeInterval, scene: SKScene) {
        guard enabled else { return }
        let dt = CGFloat(max(0, now - (lastClock ?? now)))
        lastClock = now
        simulationTime += TimeInterval(dt)
        for index in fragments.indices.reversed() {
            var fragment = fragments[index]
            let previous = fragment.node.position
            let state = fragment.motion.sample(at: simulationTime)
            let oldAngle = fragment.node.zRotation
            let oldBounds = SnowContour.bounds(SnowContour.transformed(fragment.polygons, position: previous, angle: oldAngle))
            let newBounds = SnowContour.bounds(SnowContour.transformed(fragment.polygons, position: state.position, angle: state.rotation))
            if state.position.y < previous.y && !fullscreenActive {
                for surface in receivers where surface.id != fragment.sourceID {
                    guard let plane = impactPlane(surface, x: newBounds.midX, footprint: newBounds.width, fallingSlab: true),
                          let t = SnowSweep.crossing(from: CGPoint(x: oldBounds.midX, y: oldBounds.minY),
                            to: CGPoint(x: newBounds.midX, y: newBounds.minY), plane: plane, previousTop: oldBounds.maxY) else { continue }
                    let point = CGPoint(x: previous.x + t * (state.position.x - previous.x), y: previous.y + t * (state.position.y - previous.y))
                    receive(&fragment, on: surface, position: point, angle: oldAngle + t * (state.rotation - oldAngle))
                    if fragment.volume <= 0.1 { break }
                }
            }
            if fragment.volume <= 0.1 {
                fragment.node.removeFromParent()
                fragments.remove(at: index)
                continue
            }
            fragment.node.position = state.position
            fragment.node.zRotation = state.rotation
            let remainingWorld = SnowContour.transformed(fragment.polygons, position: state.position, angle: state.rotation)
            let remainingBounds = SnowContour.bounds(remainingWorld)
            let floorHeight = ground?.height(at: remainingBounds.midX) ?? 0
            if state.finished || remainingBounds.minY <= floorHeight + 0.5 {
                SnowDiagnostics.record("Sol : origine=\(fragment.sourceID), volume=\(fragment.volume), receveurs=\(receivers.map { $0.id })")
                for polygon in remainingWorld {
                    let bounds = SnowContour.bounds([polygon])
                    ground?.add(volume: SnowContour.area(polygon), x: min(scene.size.width - 1, max(0, bounds.midX)), spread: bounds.width)
                }
                groundDirty = true
                fragment.node.removeFromParent()
                fragments.remove(at: index)
            } else if state.position.x < -200 || state.position.x > scene.size.width + 200 {
                fragment.node.removeFromParent()
                fragments.remove(at: index)
            } else {
                fragments[index] = fragment
            }
        }
        redrawTime += dt
        if redrawTime >= 0.1 {
            for id in dirtySurfaces { if let surface = surfaces[id] { redraw(surface) } }
            dirtySurfaces.removeAll()
            redrawTime = 0
        }
        plowCooldown = max(0, plowCooldown - dt)
        if plow == nil && (requestedPlow || (automaticPlow && plowCooldown == 0 && ((ground?.peak ?? 0) >= 10 || (ground?.average ?? 0) >= 2.5))) {
            requestedPlow = false
            startPlow(in: scene)
        }
        if let plow {
            plow.position.x += (season == .winter ? 155 : 115) * dt
            let bladeX = plow.position.x + 35
            pushedVolume += ground?.sweep(from: sweptUntil, to: bladeX) ?? 0
            sweptUntil = bladeX
            groundDirty = true
            let h = min(21, sqrt(pushedVolume) * 0.38)
            let mound = CGMutablePath()
            mound.move(to: CGPoint(x: 32, y: 0))
            mound.addQuadCurve(to: CGPoint(x: 32 + h * 1.5, y: 0), control: CGPoint(x: 35, y: h * 1.8))
            mound.closeSubpath()
            plowPile?.path = mound
            if plow.position.x > scene.size.width + 90 {
                plow.removeFromParent()
                self.plow = nil
                plowPile = nil
                plowCooldown = 25
            }
        }
        groundDrawTime += dt
        if groundDirty && groundDrawTime >= 0.1 {
            drawGround()
            groundDrawTime = 0
            groundDirty = false
        }
    }

    private func drawGround() {
        guard let ground else { return }
        groundNode.isHidden = !enabled || ground.peak < 0.01
        groundNode.path = ground.peak < 0.01 ? nil : ground.contourPath()
    }

    private func startPlow(in scene: SKScene) {
        let root = SKNode()
        root.zPosition = 5
        root.position = CGPoint(x: -85, y: 3)
        func box(_ rect: CGRect, _ color: NSColor, radius: CGFloat = 2) {
            let shape = SKShapeNode(rect: rect, cornerRadius: radius)
            shape.fillColor = color
            shape.strokeColor = .clear
            root.addChild(shape)
        }
        if season == .winter {
            box(CGRect(x: -30, y: 7, width: 56, height: 16), .systemOrange)
            box(CGRect(x: -5, y: 20, width: 22, height: 22), .systemRed, radius: 4)
            box(CGRect(x: -1, y: 25, width: 14, height: 13), NSColor(calibratedRed: 0.4, green: 0.78, blue: 0.95, alpha: 1))
            box(CGRect(x: 1, y: 43, width: 9, height: 4), .systemYellow)
            for x: CGFloat in [-19, 16] {
                let wheel = SKShapeNode(circleOfRadius: 7)
                wheel.fillColor = NSColor(white: 0.17, alpha: 1)
                wheel.strokeColor = NSColor(white: 0.6, alpha: 1)
                wheel.lineWidth = 2
                wheel.position = CGPoint(x: x, y: 7)
                root.addChild(wheel)
            }
            let blade = SKShapeNode(rectOf: CGSize(width: 7, height: 24), cornerRadius: 2)
            blade.fillColor = NSColor(white: 0.78, alpha: 1)
            blade.strokeColor = .clear
            blade.position = CGPoint(x: 31, y: 12)
            blade.zRotation = -0.22
            root.addChild(blade)
        } else {
            let outfit: NSColor = season == .autumn ? .systemOrange : season == .spring ? .systemGreen : .systemBlue
            box(CGRect(x: -16, y: 17, width: 14, height: 20), outfit)
            box(CGRect(x: -13, y: 36, width: 11, height: 12), .systemBrown, radius: 5)
            box(CGRect(x: -16, y: 46, width: 19, height: 4), outfit)
            for direction: CGFloat in [-1, 1] {
                let leg = SKShapeNode(rect: CGRect(x: -2, y: -15, width: 5, height: 17), cornerRadius: 2)
                leg.fillColor = .darkGray
                leg.strokeColor = .clear
                leg.position = CGPoint(x: -9, y: 18)
                leg.zRotation = direction * 0.35
                root.addChild(leg)
                leg.run(.repeatForever(.sequence([
                    .rotate(toAngle: direction * -0.45, duration: 0.22),
                    .rotate(toAngle: direction * 0.45, duration: 0.22)
                ])))
            }
            box(CGRect(x: -8, y: 24, width: 20, height: 5), .systemBrown)
            let handle = SKShapeNode(rectOf: CGSize(width: season == .autumn ? 35 : 38, height: season == .autumn ? 5 : 3))
            handle.fillColor = season == .autumn ? .darkGray : .systemBrown
            handle.strokeColor = .clear
            handle.position = CGPoint(x: 18, y: 17)
            handle.zRotation = -0.52
            root.addChild(handle)
            switch season {
            case .autumn:
                box(CGRect(x: -23, y: 20, width: 9, height: 16), .systemRed)
                box(CGRect(x: 6, y: 20, width: 13, height: 9), .systemRed)
            case .spring:
                box(CGRect(x: 30, y: 3, width: 12, height: 10), .systemYellow)
            case .summer:
                box(CGRect(x: 29, y: 8, width: 14, height: 3), .lightGray)
                for x in stride(from: 30, through: 42, by: 3) {
                    box(CGRect(x: x, y: 3, width: 1, height: 6), .lightGray)
                }
            case .winter: break
            }
        }
        let pile = SKShapeNode()
        pile.fillColor = season.depositColor
        pile.strokeColor = .clear
        root.addChild(pile)
        (backgroundLayer ?? scene).addChild(root)
        plow = root
        plowPile = pile
        sweptUntil = -100
        pushedVolume = 0
    }

    private func reset() {
        surfaces.values.forEach { $0.node.removeFromParent() }
        surfaces.removeAll()
        receivers.removeAll()
        dirtySurfaces.removeAll()
        fragments.forEach { $0.node.removeFromParent() }
        fragments.removeAll()
        resetClock()
        if let ground { self.ground = GroundSnow(width: ground.width) }
        groundNode.path = nil
        plow?.removeFromParent()
        plow = nil
        plowPile = nil
        requestedPlow = false
    }
}
