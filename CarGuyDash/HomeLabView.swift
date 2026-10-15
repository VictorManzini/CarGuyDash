#if DEBUG
import SwiftUI

/// Debug only: candidate home screens, so the owner can compare them before the real Dashboard changes.
/// Each one is drawn for a fixed state; it only reads the active car (name, first gauge, its range). The buttons do nothing.
/// Screenshots: `-openHomePreview A` and `-homePreview.state off` (searching, ready, reconnecting).
struct HomeLabView: View {
    let scanner: BluetoothScanner
    /// "A" (more to come).
    let direction: String
    @AppStorage("homePreview.state") private var stateName = "off"
    @State private var unitSettings = UnitSettings()
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    var body: some View {
        Group {
            switch direction {
            default: cockpit
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
        .preferredColorScheme(.dark)
        .navigationTitle("Dashboard")
        .navigationBarTitleDisplayMode(.inline)
        // It stands in for the home screen, so no way "back" to the real one.
        .navigationBarBackButtonHidden()
    }

    // MARK: - Shared

    private var state: ConnectionState {
        ["searching": .searching, "ready": .ready, "reconnecting": .reconnecting][stateName] ?? .disconnected
    }

    private var isDisconnected: Bool { state == .disconnected }
    /// Landscape iPhone.
    private var wide: Bool { verticalSizeClass == .compact }
    private var carName: String { scanner.profiles.active?.name ?? "Unknown car" }

    /// Color next to the state's text (never the color alone).
    private var statusColor: Color {
        switch state {
        case .ready: GaugeColor.green.color
        case .searching, .connecting: GaugeColor.blue.color
        case .reconnecting: GaugeColor.orange.color
        case .bluetoothOff: GaugeColor.red.color
        case .disconnected: GaugeLook.secondary
        }
    }

    private var statusLabel: some View {
        HStack(spacing: 6) {
            Circle().fill(statusColor).frame(width: 8, height: 8)
            Text(state.rawValue)
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }

    /// The first gauge: at the gauge editor's sample value when ready, at rest (its minimum) when off,
    /// "Stand By" while searching or reconnecting.
    private var heroGauge: some View {
        let slot = scanner.layout.visibleSlots[0]
        let source = slot.source, range = scanner.range(for: source), units = unitSettings.units
        let sample = range.rpm.map { ($0.normalLow + $0.normalHigh) / 2 } ?? range.target ?? (range.min + range.max) / 2
        let value = state == .ready ? sample : range.min
        let text = state == .ready || isDisconnected ? source.sensor.text(for: value, units: units) : "Stand By"
        let reading = GaugeReading(sensor: source.sensor, text: text, value: value, range: range, units: units, name: source.name)
        return StyledGauge(style: slot.style, finish: slot.look, reading: reading)
    }

    private func tile(_ title: String, _ systemImage: String, caption: String? = nil) -> some View {
        Button {} label: {
            VStack(spacing: 6) {
                Image(systemName: systemImage).font(.title2).symbolRenderingMode(.hierarchical)
                Text(title).font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                if let caption { Text(caption).font(.caption2).foregroundStyle(.secondary) }
            }
            .foregroundStyle(GaugeLook.primary)
            .frame(maxWidth: .infinity, minHeight: 72)
            .background(.regularMaterial, in: .rect(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(PressStyle())
    }

    /// Sensors has no page yet.
    private var pageTiles: some View {
        HStack(spacing: 12) {
            tile("Sensors", "list.bullet.rectangle", caption: "Coming soon").disabled(true)
            tile("Tests", "checklist")
            tile("Settings", "gearshape")
        }
    }

    // MARK: - A · Cockpit

    /// A: the car's own first gauge, big, in its style and look; tapping it opens the gauges page.
    private var cockpit: some View {
        let title = VStack(spacing: 4) {
            Text(carName).font(.title2.weight(.bold)).lineLimit(1).minimumScaleFactor(0.7)
            statusLabel
        }
        let hero = Button {} label: { heroGauge }
            .buttonStyle(PressStyle())
            .accessibilityLabel("Gauges")
        let connect = Button {} label: {
            Label(isDisconnected ? "Connect" : "Disconnect", systemImage: "power")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(isDisconnected ? .accentColor : .red)

        return Group {
            if wide {
                HStack(spacing: 24) {
                    hero
                    VStack(spacing: 12) {
                        title
                        Spacer(minLength: 0)
                        connect
                        pageTiles
                    }
                }
            } else {
                VStack(spacing: 16) {
                    title
                    hero.padding(.horizontal, 24)
                    connect
                    pageTiles
                }
            }
        }
    }
}

/// Instant, native press feedback: shrinks a little with a critically damped spring;
/// with Reduce Motion it dims instead. Disabled: faded.
private struct PressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .opacity(!isEnabled ? 0.4 : configuration.isPressed && reduceMotion ? 0.7 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 1), value: configuration.isPressed)
    }
}

#Preview {
    NavigationStack { HomeLabView(scanner: BluetoothScanner(), direction: "A") }
}
#endif
