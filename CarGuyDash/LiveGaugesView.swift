#if DEBUG
import SwiftUI

/// Debug only: the gauges of the active car's layout (Settings → Gauges) with real values, each in its own style.
/// Same data as the Dashboard (LiveData, `gaugeText`, the units from Settings).
struct LiveGaugesView: View {
    let scanner: BluetoothScanner
    @State private var unitSettings = UnitSettings()

    var body: some View {
        // Redraws twice a second, so a value turns "N/A" even when nothing new arrives.
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            VStack(spacing: GaugeLook.gap) {
                Text("\(scanner.carName) · \(scanner.statusText)").font(.caption).foregroundStyle(.secondary)
                let slots = scanner.layout.visibleSlots
                GaugeGrid(count: slots.count) { gauge(slots[$0]) }
            }
            .padding(.horizontal)
        }
        .navigationTitle("Live gauges")
        .navigationBarTitleDisplayMode(.inline)
        .background(.black)
        .preferredColorScheme(.dark)
        .task {
            // Simulator check without taps: `-liveGauges.autoStart YES` uses the simulated adapter and starts polling.
            guard UserDefaults.standard.bool(forKey: "liveGauges.autoStart") else { return }
            await scanner.useSimulatedAdapter()
            if scanner.needsCarInfo { scanner.skipCarInfo() }
            scanner.startPolling()
        }
    }

    /// Same value and text as the Dashboard block; the Boost is manifold − atmospheric.
    private func gauge(_ slot: GaugeSlot) -> some View {
        let source = slot.source
        let value = source == .boost ? scanner.liveData.boost : scanner.liveData.value(for: source.sensor)
        let text = gaugeText(for: source.sensor, state: scanner.state, value: value, silent: scanner.carSilent, units: unitSettings.units)
        let reading = GaugeReading(sensor: source.sensor, text: text, value: value, range: scanner.range(for: source),
                                   units: unitSettings.units, name: source.name)
        return StyledGauge(style: slot.style, reading: reading)
    }
}

#Preview {
    NavigationStack { LiveGaugesView(scanner: BluetoothScanner()) }
}
#endif
