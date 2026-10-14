import SwiftUI

/// Home screen: car name and status, Connect / Disconnect, and one big button per page.
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
    #endif

    /// Landscape iPhones are short, so the page buttons sit in two columns there.
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("\(scanner.carName) · \(scanner.statusText)").font(.headline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                connectButton
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: verticalSizeClass == .compact ? 2 : 1), spacing: 12) {
                    NavigationLink { LiveGaugesView(scanner: scanner) } label: {
                        pageLabel("Gauges", systemImage: "gauge.with.dots.needle.67percent")
                    }
                    // No page yet: disabled, with a caption.
                    Button {} label: { pageLabel("Sensors", systemImage: "list.bullet.rectangle", caption: "Coming soon") }
                        .disabled(true)
                    NavigationLink { ContentView(scanner: scanner) } label: {
                        pageLabel("Tests", systemImage: "checklist")
                    }
                    NavigationLink { SettingsView(unitSettings: unitSettings, scanner: scanner) } label: {
                        pageLabel("Settings", systemImage: "gearshape")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding()
        }
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

    /// Becomes Disconnect once the adapter is not disconnected.
    private var connectButton: some View {
        let isDisconnected = scanner.state == .disconnected
        return Button {
            if isDisconnected { scanner.connect() } else { scanner.disconnect() }
        } label: {
            Text(isDisconnected ? "Connect" : "Disconnect").font(.title3.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 36)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(isDisconnected ? .accentColor : .red)
    }

    /// Icon on the left, title next to it, optional small caption under the title. Same height for every button.
    private func pageLabel(_ title: String, systemImage: String, caption: String? = nil) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage).font(.title2).frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title3.weight(.semibold))
                if let caption { Text(caption).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 48)
    }
}

#Preview {
    NavigationStack { DashboardView(scanner: BluetoothScanner(), unitSettings: UnitSettings()) }
}
