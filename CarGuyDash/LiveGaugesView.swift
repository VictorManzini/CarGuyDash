#if DEBUG
import SwiftUI

/// Debug only: the gauges of the saved layout (Settings → Gauges) with real values, each in its own style.
/// Same data as the Dashboard (LiveData, `gaugeText`, the units from Settings).
struct LiveGaugesView: View {
    let scanner: BluetoothScanner
    @State private var ranges = GaugeRangeSettings()
    @State private var unitSettings = UnitSettings()

    var body: some View {
        // Redraws twice a second, so a value turns "N/A" even when nothing new arrives.
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            VStack(spacing: 8) {
                Text("\(scanner.carName) · \(scanner.statusText)").font(.caption).foregroundStyle(.secondary)
                GeometryReader { geo in
                    let slots = scanner.gaugeLayout.layout.visibleSlots
                    let grid = Self.grid(for: slots.count, wide: geo.size.width > geo.size.height)
                    VStack(spacing: 0) {
                        ForEach(0..<grid.rows, id: \.self) { row in
                            HStack(spacing: 0) {
                                ForEach(0..<grid.columns, id: \.self) { column in
                                    let index = row * grid.columns + column
                                    Group {
                                        if index < slots.count { gauge(slots[index]).padding(8) } else { Color.clear }
                                    }
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                }
                            }
                        }
                    }
                }
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

    /// Portrait: 1 = full screen, 2 = two rows, 3–4 = 2×2, 5–6 = two columns of three. Landscape swaps rows and columns.
    static func grid(for count: Int, wide: Bool) -> (columns: Int, rows: Int) {
        let portrait = switch count {
        case ...1: (columns: 1, rows: 1)
        case 2: (columns: 1, rows: 2)
        case 3...4: (columns: 2, rows: 2)
        default: (columns: 2, rows: 3)
        }
        return wide ? (portrait.rows, portrait.columns) : portrait
    }

    /// Same value and text as the Dashboard block; the Boost is manifold − atmospheric.
    @ViewBuilder private func gauge(_ slot: GaugeSlot) -> some View {
        let source = slot.source
        let value = source == .boost ? scanner.liveData.boost : scanner.liveData.value(for: source.sensor)
        let text = gaugeText(for: source.sensor, state: scanner.state, value: value, silent: scanner.carSilent, units: unitSettings.units)
        let reading = GaugeReading(sensor: source.sensor, text: text, value: value, range: ranges.range(for: source),
                                   units: unitSettings.units, name: source.name)
        switch slot.style {
        case .analog: AnalogGauge(reading: reading)
        case .digital: DigitalGauge(reading: reading)
        case .bar: BarGauge(reading: reading)
        case .arc: ArcGauge(reading: reading)
        }
    }
}

#Preview {
    NavigationStack { LiveGaugesView(scanner: BluetoothScanner()) }
}
#endif
