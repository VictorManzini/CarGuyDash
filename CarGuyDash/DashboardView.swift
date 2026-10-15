import SwiftUI

/// Home screen: the active car as a Wallet-style card (name, masked VIN, connection state), Connect / Disconnect,
/// and one tile per page; Gauges turns green once the adapter is ready.
struct DashboardView: View {
    let scanner: BluetoothScanner
    let unitSettings: UnitSettings
    #if DEBUG
    /// Screenshots: launching with `-openGaugePreview YES` opens the gauge preview directly.
    @State private var openGaugePreview = UserDefaults.standard.bool(forKey: "openGaugePreview")
    /// Simulator check: `-openLiveGauges YES` opens the live gauges directly.
    @State private var openLiveGauges = UserDefaults.standard.bool(forKey: "openLiveGauges")
    /// Simulator check: `-openGaugeEditor YES` opens the active car's gauge editor (Settings → Cars → car → Gauges) directly.
    @State private var openGaugeEditor = UserDefaults.standard.bool(forKey: "openGaugeEditor")
    /// Screenshots: `-openGaugeLab YES` opens the gauge look lab directly.
    @State private var openGaugeLab = UserDefaults.standard.bool(forKey: "openGaugeLab")
    /// Screenshots: `-openSettings YES` and `-openTests YES` open those screens directly.
    @State private var openSettings = UserDefaults.standard.bool(forKey: "openSettings")
    @State private var openTests = UserDefaults.standard.bool(forKey: "openTests")
    /// Screenshots: `-openSensorRange 05` opens the active car's range editor for that source (PID or "boost").
    @State private var openSensorRange = UserDefaults.standard.string(forKey: "openSensorRange").flatMap(GaugeSource.init(rawValue:))
    /// Screenshots: `-openHomePreview A` opens that candidate home screen (`HomeLabView`).
    @State private var openHomePreview = UserDefaults.standard.string(forKey: "openHomePreview")
    #endif

    var body: some View {
        // Scrolls only when it does not fit (large Dynamic Type); otherwise the card sits on top, the buttons at the bottom.
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 16) {
                    carCard
                    Spacer(minLength: 0)
                    connectButton
                    pageGrid
                }
                .padding()
                .frame(minHeight: geo.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(.black)
        .preferredColorScheme(.dark)
        .animation(.spring(response: 0.4, dampingFraction: 1), value: scanner.state)
        // Swiping the screen down closes it without saving: "Unknown car" until the next connection.
        .sheet(isPresented: Binding(get: { scanner.needsCarInfo }, set: { if !$0 { scanner.skipCarInfo() } })) {
            CarInfoView(scanner: scanner)
        }
        #if DEBUG
        .navigationDestination(isPresented: $openGaugePreview) { GaugePreviewView(scanner: scanner) }
        .navigationDestination(isPresented: $openLiveGauges) { LiveGaugesView(scanner: scanner) }
        .navigationDestination(isPresented: $openGaugeLab) { GaugeLabView(scanner: scanner) }
        .navigationDestination(isPresented: $openSettings) { SettingsView(unitSettings: unitSettings, scanner: scanner) }
        .navigationDestination(isPresented: $openTests) { ContentView(scanner: scanner) }
        .navigationDestination(item: $openHomePreview) { HomeLabView(scanner: scanner, direction: $0) }
        .task {
            // Simulator screenshots in landscape (it cannot be rotated without the Simulator window): `-forceLandscape YES`.
            guard UserDefaults.standard.bool(forKey: "forceLandscape"),
                  let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight))
        }
        .navigationDestination(isPresented: $openGaugeEditor) {
            if let car = scanner.profiles.active {
                GaugeLayoutEditor(units: unitSettings.units, profiles: scanner.profiles, carID: car.id)
            } else {
                ContentUnavailableView("No cars yet", systemImage: "car")
            }
        }
        .navigationDestination(item: $openSensorRange) { source in
            if let car = scanner.profiles.active {
                SensorRangeEditor(source: source, units: unitSettings.units, profiles: scanner.profiles, carID: car.id)
            }
        }
        #endif
        .navigationTitle("Dashboard")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// The active car (the one whose gauges show), like a card in Wallet: a generic car symbol, the state on top,
    /// the name and the masked VIN at the bottom.
    private var carCard: some View {
        let car = scanner.profiles.active
        let status = HomeStatus(state: scanner.state, silent: scanner.carSilent)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                Image(systemName: "car.side.fill").font(.largeTitle).accessibilityHidden(true)
                Spacer()
                HStack(spacing: 6) {
                    Circle().fill(status.color?.color ?? GaugeLook.secondary).frame(width: 8, height: 8)
                    Text(status.text)
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.thinMaterial, in: .capsule)
                .accessibilityElement(children: .combine)
            }
            Spacer(minLength: 16)
            Text(car?.name ?? "Unknown car").font(.title.weight(.bold)).lineLimit(1).minimumScaleFactor(0.7)
            Text(car?.vinLabel ?? "No car saved yet").font(.footnote.monospaced()).foregroundStyle(.secondary)
        }
        .foregroundStyle(GaugeLook.primary)
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // A bank card's proportions.
        .aspectRatio(1.586, contentMode: .fit)
        .background(LinearGradient(colors: [Color(white: 0.25), Color(white: 0.1)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: .rect(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(.white.opacity(0.1)))
    }

    /// Becomes Disconnect once the adapter is not disconnected.
    private var connectButton: some View {
        let isDisconnected = scanner.state == .disconnected
        return Button {
            if isDisconnected { scanner.connect() } else { scanner.disconnect() }
        } label: {
            Label(isDisconnected ? "Connect" : "Disconnect", systemImage: "power")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(isDisconnected ? .accentColor : .red)
    }

    /// Two by two: Gauges (green once ready) and Sensors (no page yet), Tests and Settings.
    private var pageGrid: some View {
        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                NavigationLink { LiveGaugesView(scanner: scanner) } label: {
                    tile("Gauges", "gauge.with.dots.needle.67percent", lit: scanner.state == .ready)
                }
                Button {} label: { tile("Sensors", "list.bullet.rectangle", caption: "Coming soon") }
                    .disabled(true)
            }
            GridRow {
                NavigationLink { ContentView(scanner: scanner) } label: { tile("Tests", "checklist") }
                NavigationLink { SettingsView(unitSettings: unitSettings, scanner: scanner) } label: { tile("Settings", "gearshape") }
            }
        }
        .buttonStyle(PressStyle())
    }

    /// Symbol, title and an optional caption on a material tile; `lit` = green with black ink.
    private func tile(_ title: String, _ systemImage: String, caption: String? = nil, lit: Bool = false) -> some View {
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
}

/// The state shown on the car card: the same text as `BluetoothScanner.statusText`, and the color of the dot next to it
/// (nil = grey). The text always says it too, so the color is never the only sign.
nonisolated struct HomeStatus: Equatable {
    let text: String
    let color: GaugeColor?
}

nonisolated extension HomeStatus {
    init(state: ConnectionState, silent: Bool) {
        text = silent ? "Ignition off?" : state.rawValue
        color = if silent {
            .yellow
        } else {
            switch state {
            case .ready: .green
            case .searching, .connecting: .blue
            case .reconnecting: .orange
            case .bluetoothOff: .red
            case .disconnected: nil
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
    NavigationStack { DashboardView(scanner: BluetoothScanner(), unitSettings: UnitSettings()) }
}
