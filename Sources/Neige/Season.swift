import AppKit
import SpriteKit

enum Season: String, CaseIterable {
    case winter = "Hiver", spring = "Printemps", summer = "Été", autumn = "Automne"

    static var current: Self {
        switch Calendar.current.component(.month, from: Date()) {
        case 3...5: .spring
        case 6...8: .summer
        case 9...11: .autumn
        default: .winter
        }
    }

    var colors: [NSColor] {
        switch self {
        case .winter: [.white]
        case .spring: [.systemPink, .systemPurple, .white]
        case .summer: [.systemYellow, .systemOrange, .white]
        case .autumn: [.systemOrange, .systemRed, .systemYellow, .systemBrown]
        }
    }

    var depositColor: NSColor {
        switch self {
        case .winter: NSColor(calibratedRed: 0.97, green: 0.985, blue: 1, alpha: 1)
        case .spring: NSColor(calibratedRed: 1, green: 0.71, blue: 0.83, alpha: 1)
        case .summer: NSColor(calibratedRed: 0.94, green: 0.78, blue: 0.47, alpha: 1)
        case .autumn: NSColor(calibratedRed: 0.75, green: 0.34, blue: 0.12, alpha: 1)
        }
    }

    var cleaner: String {
        switch self {
        case .winter: "chasse-neige"
        case .spring: "balayeur"
        case .summer: "ratisseur"
        case .autumn: "souffleur"
        }
    }

    func particleTexture() -> SKTexture {
        let image = NSImage(size: NSSize(width: 24, height: 24))
        image.lockFocus()
        NSColor.white.setFill()
        if self == .winter || self == .summer {
            NSBezierPath(ovalIn: NSRect(x: 3, y: 3, width: 18, height: 18)).fill()
        } else {
            let path = NSBezierPath()
            path.move(to: CGPoint(x: 3, y: 4))
            path.curve(to: CGPoint(x: 21, y: 21), controlPoint1: CGPoint(x: 0, y: 19), controlPoint2: CGPoint(x: 15, y: 22))
            path.curve(to: CGPoint(x: 3, y: 4), controlPoint1: CGPoint(x: 24, y: 8), controlPoint2: CGPoint(x: 13, y: 3))
            path.close()
            path.fill()
            if self == .autumn {
                path.removeAllPoints()
                path.move(to: CGPoint(x: 2, y: 2))
                path.line(to: CGPoint(x: 16, y: 16))
                path.lineWidth = 1
                NSColor.white.withAlphaComponent(0.85).setStroke()
                path.stroke()
            }
        }
        image.unlockFocus()
        return SKTexture(image: image)
    }
}
