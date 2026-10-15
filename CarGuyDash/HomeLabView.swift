#if DEBUG
import SwiftUI

/// Debug only: candidate home screens, so the owner can compare them before the real Dashboard changes.
/// Each one is drawn for a fixed state; it only reads the active car (name, first gauge, its range). The buttons do nothing.
/// Screenshots: `-openHomePreview A` (B to F) and `-homePreview.state off` (searching, ready, reconnecting).
struct HomeLabView: View {
    let scanner: BluetoothScanner
    /// "A" to "F".
    let direction: String
    @AppStorage("homePreview.state") private var stateName = "off"
    @State private var unitSettings = UnitSettings()
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    var body: some View {
        Group {
            switch direction {
            case "B": raceDash
            case "C": startButton
            case "D": nativeButton
            case "E": carKey
            case "F": accessories
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

    /// `lit`: green with black ink (Gauges once ready).
    private func tile(_ title: String, _ systemImage: String, caption: String? = nil, lit: Bool = false) -> some View {
        Button {} label: {
            VStack(spacing: 6) {
                Image(systemName: systemImage).font(.title2).symbolRenderingMode(.hierarchical)
                Text(title).font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                if let caption { Text(caption).font(.caption2).foregroundStyle(.secondary) }
            }
            .foregroundStyle(lit ? .black : GaugeLook.primary)
            .frame(maxWidth: .infinity, minHeight: 72)
            .background(lit ? AnyShapeStyle(GaugeColor.green.color) : AnyShapeStyle(.regularMaterial),
                        in: .rect(cornerRadius: 16, style: .continuous))
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

    // MARK: - D · Native button

    /// D: C's idea in plain iOS clothes: a big round system button with an Activity-style ring for the state,
    /// then a Gauges capsule that turns green when ready, and the page tiles.
    private var nativeButton: some View {
        let name = Text(carName).font(.largeTitle.weight(.bold)).lineLimit(1).minimumScaleFactor(0.7)
        let button = VStack(spacing: 12) {
            PowerButton(label: isDisconnected ? "Connect" : "Disconnect", ring: statusColor, state: state)
                .frame(maxWidth: 220)
            statusLabel
        }
        let ready = state == .ready
        let gauges = Button {} label: {
            Label("Gauges", systemImage: "gauge.with.dots.needle.67percent")
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(ready ? GaugeColor.green.color : Color(white: 0.2))
        .foregroundStyle(ready ? .black : GaugeLook.primary)

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

    // MARK: - E · Car key

    /// E: the car as a Wallet-style card (a generic car symbol, the name, the masked VIN, the state),
    /// Connect under it, then a 2×2 grid with Gauges lit when ready.
    private var carKey: some View {
        let card = VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                Image(systemName: "car.side.fill").font(.system(size: 40)).foregroundStyle(GaugeLook.primary)
                Spacer()
                statusLabel
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.thinMaterial, in: .capsule)
            }
            Spacer(minLength: 16)
            Text(carName).font(.title.weight(.bold)).lineLimit(1).minimumScaleFactor(0.7)
            Text(scanner.profiles.active?.vinLabel ?? "No car yet").font(.footnote.monospaced()).foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // A bank card's proportions.
        .aspectRatio(1.586, contentMode: .fit)
        .background(LinearGradient(colors: [Color(white: 0.25), Color(white: 0.1)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: .rect(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(.white.opacity(0.1)))
        let connect = Button {} label: {
            Label(isDisconnected ? "Connect" : "Disconnect", systemImage: "power")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(isDisconnected ? .accentColor : .red)
        let grid = Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                tile("Gauges", "gauge.with.dots.needle.67percent", lit: state == .ready)
                tile("Sensors", "list.bullet.rectangle", caption: "Coming soon").disabled(true)
            }
            GridRow {
                tile("Tests", "checklist")
                tile("Settings", "gearshape")
            }
        }

        return Group {
            if wide {
                HStack(spacing: 24) {
                    card
                    VStack(spacing: 12) {
                        Spacer(minLength: 0)
                        connect
                        grid
                    }
                }
            } else {
                VStack(spacing: 16) {
                    card
                    Spacer(minLength: 0)
                    connect
                    grid
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 1), value: state)
    }

    // MARK: - F · Home app

    /// F: tiles like the Home app's accessories: the adapter and Gauges as two big ones that turn light when on
    /// (connected / ready), the other pages as small ones; the car's name as a large title.
    private var accessories: some View {
        let ready = state == .ready
        let big: CGFloat = wide ? 120 : 150
        let name = Text(carName).font(.largeTitle.weight(.bold)).lineLimit(1).minimumScaleFactor(0.7)
        // As in the Home app the subtitle is only the state; what a tap does goes to VoiceOver.
        let adapter = accessory("OBD adapter", state.rawValue, "power", on: !isDisconnected, color: statusColor, height: big)
            .accessibilityHint(isDisconnected ? "Connects" : "Disconnects")
        let gauges = accessory("Gauges", "\(scanner.layout.count) gauges" + (ready ? " · Live" : ""),
                               "gauge.with.dots.needle.67percent", on: ready, color: GaugeColor.green.color, height: big)
        let sensors = accessory("Sensors", "Coming soon", "list.bullet.rectangle", on: false).disabled(true)
        let tests = accessory("Tests", "Log", "checklist", on: false)
        let settings = accessory("Settings", "Cars, units", "gearshape", on: false)

        return VStack(alignment: .leading, spacing: 12) {
            name
            Spacer(minLength: 0)
            if wide {
                HStack(spacing: 12) { adapter; gauges; sensors; tests; settings }
            } else {
                HStack(spacing: 12) { adapter; gauges }
                HStack(spacing: 12) { sensors; tests; settings }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 1), value: state)
    }

    /// F: a Home app accessory tile: the symbol in a circle on top, title and subtitle at the bottom.
    /// On: a light tile with dark ink and the symbol's circle in `color`.
    private func accessory(_ title: String, _ subtitle: String, _ systemImage: String, on: Bool, color: Color = .clear,
                           height: CGFloat = 96) -> some View {
        Button {} label: {
            VStack(alignment: .leading, spacing: 2) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(on ? .black : GaugeLook.primary)
                    .frame(width: 40, height: 40)
                    .background(on ? color : Color(white: 0.25), in: .circle)
                Spacer(minLength: 8)
                Text(title).font(.headline).lineLimit(1).minimumScaleFactor(0.8)
                Text(subtitle).font(.subheadline).opacity(0.6).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(on ? .black : GaugeLook.primary)
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: height, alignment: .topLeading)
            .background(on ? AnyShapeStyle(Color(white: 0.92)) : AnyShapeStyle(.regularMaterial),
                        in: .rect(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(PressStyle())
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// D: a round system button (material, power symbol, label) with a ring like the Activity rings: none when off,
/// a short arc that turns while searching or reconnecting (still with Reduce Motion), full when ready.
private struct PowerButton: View {
    let label: String
    let ring: Color
    let state: ConnectionState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var turning = false

    var body: some View {
        let busy = [.searching, .connecting, .reconnecting].contains(state)
        let fill: CGFloat = state == .ready ? 1 : busy ? 0.25 : 0
        Button {} label: {
            ZStack {
                Circle().fill(.regularMaterial)
                Circle().stroke(GaugeLook.unlit, lineWidth: 12).padding(10)
                Circle()
                    .trim(from: 0, to: fill)
                    .stroke(ring, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(turning ? 270 : -90))
                    .padding(10)
                VStack(spacing: 8) {
                    Image(systemName: "power")
                        .font(.system(size: 52, weight: .semibold))
                        .foregroundStyle(state == .disconnected ? Color.accentColor : ring)
                    Text(label).font(.headline)
                }
                .foregroundStyle(GaugeLook.primary)
            }
            .aspectRatio(1, contentMode: .fit)
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(label)
        .task(id: busy) {
            turning = false
            guard busy, !reduceMotion else { return }
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) { turning = true }
        }
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
