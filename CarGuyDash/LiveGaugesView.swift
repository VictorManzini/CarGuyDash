#if DEBUG
import SwiftUI

/// Debug only: the Dashboard's sensors with real values, drawn with the new gauge styles.
/// Same data as the Dashboard (LiveData, `gaugeText`, the units from Settings); it does not touch polling.
struct LiveGaugesView: View {
    let scanner: BluetoothScanner
    @AppStorage("liveGauges.style") private var style = Style.analog
    @State private var ranges = GaugeRangeSettings()
    @State private var unitSettings = UnitSettings()

    enum Style: String, CaseIterable {
        case analog = "Analog", digital = "Digital", bar = "Bar", arc = "Arc"
    }

    var body: some View {
        // Redraws twice a second, so a value turns "N/A" even when nothing new arrives.
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            ScrollView {
                VStack(spacing: 16) {
                    Picker("Style", selection: $style) {
                        ForEach(Style.allCases, id: \.self) { Text($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    Text("\(scanner.carName) · \(scanner.statusText)").font(.caption).foregroundStyle(.secondary)
                    gauge(.rpm).frame(height: 260)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible())], spacing: 24) {
                        ForEach(scanner.sensorsToPoll.filter { $0 != .rpm }, id: \.self) { sensor in
                            gauge(sensor).frame(height: 200)
                        }
                    }
                }
                .padding()
            }
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

    /// Same value and text as the Dashboard block; the manifold pressure shows the boost.
    @ViewBuilder private func gauge(_ sensor: Sensor) -> some View {
        let isBoost = sensor == .manifoldPressure
        let value = isBoost ? scanner.liveData.boost : scanner.liveData.value(for: sensor)
        let text = gaugeText(for: sensor, state: scanner.state, value: value, silent: scanner.carSilent, units: unitSettings.units)
        let reading = GaugeReading(sensor: sensor, text: text, value: value,
                                   range: ranges.range(for: isBoost ? .boost : .sensor(sensor)),
                                   units: unitSettings.units, name: isBoost ? "Boost" : nil)
        switch style {
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
