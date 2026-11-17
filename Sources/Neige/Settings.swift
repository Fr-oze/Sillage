import SwiftUI

final class Settings: ObservableObject {
    @Published var seasonChoice: Season? { didSet { save() } }
    var season: Season { seasonChoice ?? .current }
    @Published var enabled: Bool { didSet { save() } }
    @Published var amount: Double { didSet { save() } }
    @Published var size: Double { didSet { save() } }
    @Published var speed: Double { didSet { save() } }
    @Published var wind: Double { didSet { save() } }
    @Published var accumulateWindows: Bool { didSet { save() } }
    @Published var accumulateDock: Bool { didSet { save() } }
    @Published var behindWindows: Bool { didSet { save() } }
    @Published var automaticPlow: Bool { didSet { save() } }
    @Published var cartoonPause: Bool { didSet { save() } }
    @Published var dockEstimated = false
    var onChange: (() -> Void)?

    init() {
        let d = UserDefaults.standard
        d.register(defaults: ["enabled": true, "amount": 0.5, "size": 1.0, "speed": 1.0, "wind": 0.0, "accumulateWindows": true, "accumulateDock": true, "behindWindows": false, "automaticPlow": true, "cartoonPause": true])
        seasonChoice = d.string(forKey: "season").flatMap(Season.init(rawValue:))
        cartoonPause = d.bool(forKey: "cartoonPause")
        automaticPlow = d.bool(forKey: "automaticPlow")
        accumulateWindows = d.bool(forKey: "accumulateWindows")
        accumulateDock = d.bool(forKey: "accumulateDock")
        behindWindows = d.bool(forKey: "behindWindows")
        enabled = d.bool(forKey: "enabled")
        amount = Self.clamp(d.double(forKey: "amount"), 0...1)
        size = Self.clamp(d.double(forKey: "size"), 0.5...2.5)
        speed = Self.clamp(d.double(forKey: "speed"), 0.25...3)
        wind = Self.clamp(d.double(forKey: "wind"), -100...100)
    }
    private static func clamp(_ x: Double, _ r: ClosedRange<Double>) -> Double {
        x.isFinite ? min(r.upperBound, max(r.lowerBound, x)) : r.lowerBound
    }
    private func save() {
        let d = UserDefaults.standard
        d.set(seasonChoice?.rawValue, forKey: "season")
        d.set(cartoonPause, forKey: "cartoonPause")
        d.set(automaticPlow, forKey: "automaticPlow")
        d.set(accumulateWindows, forKey: "accumulateWindows")
        d.set(accumulateDock, forKey: "accumulateDock")
        d.set(behindWindows, forKey: "behindWindows")
        d.set(enabled, forKey: "enabled")
        d.set(amount, forKey: "amount")
        d.set(size, forKey: "size")
        d.set(speed, forKey: "speed")
        d.set(wind, forKey: "wind")
        onChange?()
    }
}

struct ControlsView: View {
    @ObservedObject var settings: Settings
    let close: () -> Void
    let plow: () -> Void
    private var theme: (icon: String, accent: Color) {
        switch settings.season {
        case .winter: ("snowflake", .cyan)
        case .spring: ("camera.macro", .pink)
        case .summer: ("sun.max.fill", .yellow)
        case .autumn: ("leaf.fill", .orange)
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                Image(systemName: theme.icon)
                    .font(.system(size: 25, weight: .medium))
                    .foregroundStyle(theme.accent)
                    .frame(width: 52, height: 52)
                    .background(theme.accent.opacity(0.16), in: RoundedRectangle(cornerRadius: 16))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Sillage").font(.system(size: 28, weight: .semibold, design: .rounded))
                    Text(settings.season.rawValue).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Activer l’effet", isOn: $settings.enabled)
                    .toggleStyle(.switch).labelsHidden()
            }
            .padding(16)
            .background(
                LinearGradient(colors: [theme.accent.opacity(0.22), theme.accent.opacity(0.04)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 18)
            )

            card("Ambiance", icon: "slider.horizontal.3") {
                Picker("Saison", selection: $settings.seasonChoice) {
                    Text("Automatique").tag(nil as Season?)
                    ForEach(Season.allCases, id: \.self) { season in
                        Text(season.rawValue).tag(Optional(season))
                    }
                }
                .pickerStyle(.menu)

                Grid(horizontalSpacing: 20, verticalSpacing: 9) {
                    GridRow {
                        control("Quantité", value: $settings.amount, range: 0...1, text: "\(Int(settings.amount * 100)) %")
                        control("Taille", value: $settings.size, range: 0.5...2.5, text: String(format: "× %.1f", settings.size))
                    }
                    GridRow {
                        control("Vitesse", value: $settings.speed, range: 0.25...3, text: String(format: "× %.1f", settings.speed))
                        control("Vent", value: $settings.wind, range: -100...100, text: abs(settings.wind) < 1 ? "Calme" : (settings.wind < 0 ? "← " : "→ ") + "\(Int(abs(settings.wind)))")
                    }
                }
            }

            card("Fenêtres et nettoyage", icon: "macwindow") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Accumulation sur les fenêtres", isOn: $settings.accumulateWindows)
                    Toggle("Accumulation sur le Dock", isOn: $settings.accumulateDock)
                    if settings.accumulateDock && settings.dockEstimated {
                        Text("Le bord du Dock est indisponible sur ce macOS.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Toggle("Effet seulement derrière les fenêtres", isOn: $settings.behindWindows)
                    if settings.behindWindows {
                        Text("L’accumulation est masquée dans ce mode.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Toggle("Pause cartoon avant la chute", isOn: $settings.cartoonPause)
                    Toggle("Nettoyage automatique au bas de l’écran", isOn: $settings.automaticPlow)
                }
                .toggleStyle(.checkbox)
            }

            HStack {
                Button(action: plow) {
                    Label("Faire passer le \(settings.season.cleaner)", systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!settings.enabled || settings.behindWindows)
                Spacer()
                Button("Fermer", action: close).buttonStyle(.bordered)
            }
        }
        .controlSize(.regular)
        .tint(theme.accent)
        .padding(18)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func card<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon).font(.subheadline.weight(.semibold))
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14).strokeBorder(.primary.opacity(0.08))
        }
    }

    private func control(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(text).monospacedDigit().foregroundStyle(.secondary)
            }
            .font(.caption)
            Slider(value: value, in: range).accessibilityLabel(title)
        }
        .frame(maxWidth: .infinity)
    }
}
