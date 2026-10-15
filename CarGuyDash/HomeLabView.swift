#if DEBUG
import SwiftUI

/// Debug only: candidate home screens, so the owner can compare them before the real Dashboard changes.
/// Each one is drawn for a fixed state; it only reads the active car (name, first gauge, its range). The buttons do nothing.
/// Screenshots: `-openHomePreview A` (B, C) and `-homePreview.state off` (searching, ready, reconnecting).
struct HomeLabView: View {
    let scanner: BluetoothScanner
    /// "A", "B" or "C".
    let direction: String
    @AppStorage("homePreview.state") private var stateName = "off"
    @State private var unitSettings = UnitSettings()
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    var body: some View {
        Group {
            switch direction {
            case "B": raceDash
            case "C": startButton
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

    // MARK: - B · Race dash

    /// B: ten status lights, the car's name big and condensed, numbered blocks with Gauges as the big orange one.
    private var raceDash: some View {
        let name = Text(carName.uppercased())
            .font(.largeTitle.weight(.heavy).width(.condensed))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        let status = Text(state.rawValue.uppercased())
            .font(.subheadline.weight(.bold).width(.condensed))
            .tracking(1.5)
            .foregroundStyle(statusColor)
        let gauges = block("01", "Gauges", "gauge.with.dots.needle.67percent", fill: GaugeColor.orange.color, ink: .black,
                           height: wide ? 110 : 136)
        let sensors = block("02", "Sensors", "list.bullet.rectangle", caption: "Soon").disabled(true)
        let tests = block("03", "Tests", "checklist")
        let settings = block("04", "Settings", "gearshape")
        let connect = block("", isDisconnected ? "Connect" : "Disconnect", "power",
                            fill: isDisconnected ? .accentColor : GaugeColor.red.color, ink: .white)

        return Group {
            if wide {
                VStack(spacing: 12) {
                    StatusLights(state: state, color: statusColor)
                    HStack(alignment: .firstTextBaseline) { name; Spacer(); status }
                    Spacer(minLength: 0)
                    HStack(spacing: 12) { gauges; sensors; tests; settings; connect }
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    StatusLights(state: state, color: statusColor)
                    name.padding(.top, 8)
                    status
                    Spacer(minLength: 0)
                    gauges
                    HStack(spacing: 12) { sensors; tests }
                    HStack(spacing: 12) { settings; connect }
                }
            }
        }
    }

    /// A race dash block: number and symbol on top, the title in heavy condensed capitals at the bottom.
    private func block(_ number: String, _ title: String, _ systemImage: String, caption: String? = nil,
                       fill: Color? = nil, ink: Color = GaugeLook.primary, height: CGFloat? = nil) -> some View {
        Button {} label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(number).font(.caption.weight(.bold).width(.condensed)).monospacedDigit()
                    Spacer()
                    Image(systemName: systemImage).font(.title3)
                }
                Spacer(minLength: 8)
                Text(title.uppercased()).font(.title3.weight(.heavy).width(.condensed)).lineLimit(1).minimumScaleFactor(0.7)
                if let caption {
                    Text(caption.uppercased()).font(.caption2.weight(.bold).width(.condensed)).tracking(1).opacity(0.6)
                }
            }
            .foregroundStyle(ink)
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: height ?? (wide ? 110 : 96), alignment: .topLeading)
            .background(fill.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.regularMaterial), in: .rect(cornerRadius: 6))
        }
        .buttonStyle(PressStyle())
        // Its own height (the minimum, or more for big text), not whatever space is left.
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - C · Start button

    /// C: an engine start button for Connect / Disconnect, its ring in the state's color, then Gauges (lit when ready)
    /// and the page tiles.
    private var startButton: some View {
        let name = Text(carName).font(.title.weight(.bold)).fontDesign(.rounded).lineLimit(1).minimumScaleFactor(0.7)
        let button = VStack(spacing: 12) {
            StartButton(finish: scanner.layout.visibleSlots[0].look, label: isDisconnected ? "Connect" : "Disconnect",
                        ring: statusColor, busy: [.searching, .connecting, .reconnecting].contains(state))
                .frame(maxWidth: 240)
            statusLabel
        }
        let ready = state == .ready
        let gauges = Button {} label: {
            HStack(spacing: 12) {
                Image(systemName: "gauge.with.dots.needle.67percent").font(.title2)
                Text("Gauges").font(.title3.weight(.semibold))
                Spacer()
                Image(systemName: "chevron.right").font(.headline).opacity(0.6)
            }
            .foregroundStyle(ready ? .black : GaugeLook.primary)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(ready ? AnyShapeStyle(GaugeColor.green.color) : AnyShapeStyle(.regularMaterial),
                        in: .rect(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(PressStyle())

        return Group {
            if wide {
                HStack(spacing: 32) {
                    button
                    VStack(spacing: 12) {
                        name
                        Spacer(minLength: 0)
                        gauges
                        pageTiles
                    }
                }
            } else {
                VStack(spacing: 16) {
                    name
                    Spacer(minLength: 0)
                    button
                    Spacer(minLength: 0)
                    gauges
                    pageTiles
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 1), value: state)
    }
}

/// C: a round push-start button. The bezel and the face are the given look's (as on its round gauges),
/// inside them a ring in the state's color; the power symbol pulses while busy (not with Reduce Motion).
private struct StartButton: View {
    let finish: GaugeFinish
    let label: String
    let ring: Color
    let busy: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let spec = finish.spec
        Button {} label: {
            GeometryReader { geo in
                let r = min(geo.size.width, geo.size.height) / 2
                let bezel = max(6, r * spec.bezel * 1.5)
                ZStack {
                    Circle().fill(LinearGradient(colors: [spec.bezelTop, spec.bezelBottom], startPoint: .top, endPoint: .bottom))
                    Circle()
                        .fill(RadialGradient(colors: [spec.faceCenter, spec.faceEdge], center: .center, startRadius: 0, endRadius: r))
                        .padding(bezel)
                    Circle().strokeBorder(ring, lineWidth: max(3, r * 0.035)).padding(bezel + r * 0.07)
                    VStack(spacing: r * 0.06) {
                        Image(systemName: "power")
                            .font(.system(size: r * 0.34, weight: .semibold))
                            .symbolEffect(.pulse, isActive: busy && !reduceMotion)
                        Text(label.uppercased()).font(.headline.weight(.bold)).tracking(1.5)
                    }
                    .foregroundStyle(GaugeLook.primary)
                }
                .frame(width: 2 * r, height: 2 * r)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
            }
            .aspectRatio(1, contentMode: .fit)
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(label)
    }
}

/// B: ten lights, like a shift-light strip: dark when off, the first four lit while searching, all lit when ready
/// and while reconnecting, which blinks (steady with Reduce Motion). The state's text says the same, so it is hidden from VoiceOver.
private struct StatusLights: View {
    let state: ConnectionState
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dimmed = false

    var body: some View {
        let lit = switch state {
        case .ready, .reconnecting: 10
        case .connecting: 7
        case .searching: 4
        case .bluetoothOff, .disconnected: 0
        }
        HStack(spacing: 6) {
            ForEach(0..<10, id: \.self) { index in
                Capsule().fill(index < lit ? color : GaugeLook.unlit).frame(height: 10)
            }
        }
        .opacity(dimmed ? 0.3 : 1)
        .accessibilityHidden(true)
        .task(id: state) {
            dimmed = false
            guard state == .reconnecting, !reduceMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(0.5))
                withAnimation(.easeInOut(duration: 0.15)) { dimmed.toggle() }
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
