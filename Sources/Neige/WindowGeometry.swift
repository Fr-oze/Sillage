import AppKit
import CoreGraphics

struct SnowLedge {
    let id: CGWindowID
    let frame: CGRect
    let spans: [ClosedRange<CGFloat>]
    let isDock: Bool
    var ownerPID: pid_t = 0
    var maxSnowHeight: CGFloat = 20
}

// Aucune image ni aucun titre : seuls identifiant, PID, couche, opacité et rectangle.
enum WindowGeometry {
    // Contrairement à optionAll, optionOnScreenOnly garantit l'ordre avant/arrière.
    static let windowListOptions: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    @MainActor private(set) static var dockIsEstimated = false
    @MainActor private(set) static var fullscreenFrames: [CGRect] = []

    static func isFullscreen(_ frame: CGRect, screen: CGRect) -> Bool {
        // Une fenêtre maximisée sous la barre de menus n'est pas un plein écran.
        abs(frame.minX - screen.minX) <= 2 && abs(frame.maxX - screen.maxX) <= 2
            && abs(frame.minY - screen.minY) <= 2 && abs(frame.maxY - screen.maxY) <= 2
    }

    static func isOccluder(layer: Int, isDock: Bool) -> Bool {
        // Le conteneur transparent du Dock peut avoir la taille de l'écran.
        // Seuls les rectangles de fenêtres normales et du Dock réel occultent.
        layer == 0 || isDock
    }

    static func hasVisibleTop(_ frame: CGRect, screenFrames: [CGRect]) -> Bool {
        screenFrames.contains { screen in
            frame.maxX > screen.minX && frame.minX < screen.maxX
                && frame.maxY <= screen.maxY + 1 && frame.maxY > screen.minY
        }
    }

    static func headroom(above frame: CGRect, visibleFrames: [CGRect]) -> CGFloat {
        visibleFrames.filter { $0.maxX > frame.minX && $0.minX < frame.maxX && $0.maxY > frame.minY }
            .map { max(0, $0.maxY - frame.maxY) }.max() ?? 0
    }

    static func appKitRect(_ cgRect: CGRect, primaryTop: CGFloat) -> CGRect {
        CGRect(x: cgRect.minX, y: primaryTop - cgRect.maxY,
               width: cgRect.width, height: cgRect.height)
    }

    static func exposedSpans(of frame: CGRect, inFront: [CGRect], clearance: CGFloat = 14) -> [ClosedRange<CGFloat>] {
        var spans = [frame.minX...frame.maxX]
        for cover in inFront where cover.minY < frame.maxY + clearance && cover.maxY > frame.maxY - 1 {
            spans = spans.flatMap { span -> [ClosedRange<CGFloat>] in
                let left = max(span.lowerBound, cover.minX)
                let right = min(span.upperBound, cover.maxX)
                guard left < right else { return [span] }
                var pieces: [ClosedRange<CGFloat>] = []
                if left > span.lowerBound { pieces.append(span.lowerBound...left) }
                if right < span.upperBound { pieces.append(right...span.upperBound) }
                return pieces
            }
            if spans.isEmpty { break }
        }
        return spans.filter { $0.upperBound - $0.lowerBound >= 8 }
    }

    @MainActor
    static func visibleLedges(windows: Bool, dock: Bool) -> [SnowLedge] {
        guard windows || dock,
              let firstScreen = NSScreen.screens.first,
              let entries = CGWindowListCopyWindowInfo(windowListOptions, kCGNullWindowID) as? [[String: Any]] else { return [] }
        dockIsEstimated = false
        fullscreenFrames = []
        var frontOwners: [Int: pid_t] = [:]
        let primaryTop = firstScreen.frame.maxY
        let dockPID = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier
        var occluders: [CGRect] = []
        var ledges: [SnowLedge] = []
        var eligibleOwners: [pid_t: Bool] = [:]
        // CGWindowList renvoie les fenêtres de l'avant vers l'arrière.
        for entry in entries {
            // L'ordre de ce tableau est l'ordre visuel, sans tri supplémentaire.
            // Une fenêtre recouverte reste un support tant qu'elle est onscreen.
            guard entry[kCGWindowIsOnscreen as String] as? Bool == true,
                  let layer = entry[kCGWindowLayer as String] as? Int,
                  layer >= 0,
                  (entry[kCGWindowAlpha as String] as? Double ?? 1) > 0.05,
                  let bounds = entry[kCGWindowBounds as String] as? [String: Any],
                  let cgRect = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  cgRect.width > 1, cgRect.height > 1,
                  let id = entry[kCGWindowNumber as String] as? UInt32 else { continue }
            let frame = appKitRect(cgRect, primaryTop: primaryTop)
            let pid = entry[kCGWindowOwnerPID as String] as? pid_t
            // Les vitres de Neige sont au niveau statusBar, pas ses réglages (niveau 0).
            if pid == ProcessInfo.processInfo.processIdentifier && layer != 0 { continue }
            guard NSScreen.screens.contains(where: { $0.frame.intersects(frame) }) else { continue }
            let isDock = pid == dockPID && layer != 0 && frame.width > frame.height * 2 && frame.height >= 20 && frame.height <= 180
                && NSScreen.screens.contains(where: { abs(frame.minY - $0.frame.minY) < 24 })
            let ownerPID = pid ?? 0
            if eligibleOwners[ownerPID] == nil {
                let app = NSRunningApplication(processIdentifier: ownerPID)
                eligibleOwners[ownerPID] = ownerPID == ProcessInfo.processInfo.processIdentifier
                    || (app != nil && app!.activationPolicy != .prohibited)
            }
            if layer == 0 && eligibleOwners[ownerPID] == true && ownerPID != ProcessInfo.processInfo.processIdentifier && frame.width >= 160 && frame.height >= 80 {
                for (index, screen) in NSScreen.screens.enumerated() where frame.intersects(screen.frame) {
                    let usable = screen.visibleFrame
                    let overlap = frame.intersection(usable)
                    let covers = overlap.width >= usable.width * 0.98 && overlap.height >= usable.height * 0.98
                    if hasVisibleTop(frame, screenFrames: [usable]) || covers {
                        if frontOwners[index] == nil && isFullscreen(frame, screen: screen.frame) && !fullscreenFrames.contains(screen.frame) { fullscreenFrames.append(screen.frame) }
                        if frontOwners[index] == nil { frontOwners[index] = ownerPID }
                    }
                }
            }
            // Les fenêtres auxiliaires de rendu (boutons, effets système, snapshots)
            // ne constituent pas un appui, même lorsqu'elles ont la couche zéro.
            let headroom = headroom(above: frame, visibleFrames: NSScreen.screens.map(\.visibleFrame))
            let normalSupport = layer == 0 && eligibleOwners[ownerPID] == true
                && frame.width >= 160 && frame.height >= 80 && headroom > 2
            let candidate = (windows && normalSupport) || (dock && isDock)
            // macOS récent : le Dock peut n'exposer que son conteneur plein écran.
            if dock && pid == dockPID && layer == 20 && !isDock {
                // Un rectangle plein écran ne donne pas la position du bord du Dock.
                // Ne plus inventer un appui qui peut rester suspendu.
                dockIsEstimated = true
            }
            if candidate {
                let spans = exposedSpans(of: frame, inFront: occluders)
                // Conserver aussi les fenêtres recouvertes : les cacher ne doit pas
                // être confondu avec une fermeture et déclencher une avalanche.
                ledges.append(SnowLedge(id: id, frame: frame, spans: spans, isDock: isDock, ownerPID: ownerPID, maxSnowHeight: min(20, headroom)))
            }
            let normalCover = layer == 0 && frame.width >= 160 && frame.height >= 80
                && (hasVisibleTop(frame, screenFrames: NSScreen.screens.map(\.visibleFrame))
                    || NSScreen.screens.contains { screen in
                        let overlap = frame.intersection(screen.visibleFrame)
                        return overlap.width >= screen.visibleFrame.width * 0.98
                            && overlap.height >= screen.visibleFrame.height * 0.98
                    })
            // Un panneau d'une extension peut masquer une fenêtre sans devenir
            // lui-même un support où faire pousser de la neige.
            if normalCover || isDock { occluders.append(frame) }
        }
        return ledges
    }

}
