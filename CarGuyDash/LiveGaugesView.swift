import SwiftUI

/// The gauges page (the Dashboard's "Gauges" button): the active car's layout (Settings → Gauges) with live values,
/// each gauge in its own style.
/// Same data as the Dashboard (LiveData, `gaugeText`, the units from Settings).
struct LiveGaugesView: View {
    let scanner: BluetoothScanner
    @State private var unitSettings = UnitSettings()
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    var body: some View {
        // Redraws twice a second, so a value turns "N/A" even when nothing new arrives.
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            VStack(spacing: GaugeLook.gap) {
                // Landscape: the gauges get the whole screen.
                if verticalSizeClass != .compact {
                    Text("\(scanner.carName) · \(scanner.statusText)").font(.caption).foregroundStyle(.secondary)
                }
                let slots = scanner.layout.visibleSlots
                GaugeGrid(count: slots.count) { gauge(slots[$0]) }
            }
            .padding(.horizontal)
        }
        .landscapeFullScreen()
        .navigationTitle("Live gauges")
        .navigationBarTitleDisplayMode(.inline)
        .background(.black)
        .preferredColorScheme(.dark)
        #if DEBUG
        .task {
            // Simulator check without taps: `-liveGauges.autoStart YES` uses the simulated adapter and starts polling
            // (still needed: only the real adapter starts polling by itself).
            guard UserDefaults.standard.bool(forKey: "liveGauges.autoStart") else { return }
            await scanner.useSimulatedAdapter()
            if scanner.needsCarInfo { scanner.skipCarInfo() }
            scanner.startPolling()
        }
        #endif
    }

    /// Same value and text as the Dashboard block; the Boost is manifold − atmospheric.
    private func gauge(_ slot: GaugeSlot) -> some View {
        let source = slot.source
        let value = source == .boost ? scanner.liveData.boost : scanner.liveData.value(for: source.sensor)
        let text = gaugeText(for: source.sensor, state: scanner.state, value: value, silent: scanner.carSilent, units: unitSettings.units)
        let reading = GaugeReading(sensor: source.sensor, text: text, value: value, range: scanner.range(for: source),
                                   units: unitSettings.units, name: source.name)
        return StyledGauge(style: slot.style, finish: slot.look, reading: reading)
    }
}

#Preview {
    NavigationStack { LiveGaugesView(scanner: BluetoothScanner()) }
}
