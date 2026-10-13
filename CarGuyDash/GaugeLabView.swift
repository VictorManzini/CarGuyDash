#if DEBUG
import SwiftUI

/// Debug only: the three looks side by side, each as Analog RPM, Arc coolant and Bar oil, drawn by the real styles
/// (coolant 98 °C, oil 95 °C, RPM from a 0–7000 slider).
/// Screenshots: `-openGaugeLab YES -gaugeLab.rpm 6400`, and `-gaugeLab.solo A` (B, C) for one RPM dial full screen.
struct GaugeLabView: View {
    let scanner: BluetoothScanner
    @AppStorage("gaugeLab.rpm") private var rpm = 3000.0
    /// "A", "B" or "C": only that look's RPM dial, full screen. Empty = the three rows.
    @AppStorage("gaugeLab.solo") private var solo = ""
    @State private var unitSettings = UnitSettings()

    var body: some View {
        Group {
            if let finish = GaugeFinish(rawValue: solo) {
                gauge(.analog, finish, .rpm, rpm).padding(GaugeLook.gapLarge)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: GaugeLook.gapLarge) {
                        ForEach(GaugeFinish.allCases, id: \.self) { finish in
                            Text(finish.title).font(.headline)
                            HStack(spacing: GaugeLook.gap) {
                                gauge(.analog, finish, .rpm, rpm)
                                gauge(.arc, finish, .coolantTemp, 98)
                                gauge(.bar, finish, .oilTemp, 95)
                            }
                            .frame(height: 180)
                        }
                    }
                    .padding()
                }
                .safeAreaInset(edge: .bottom) {
                    VStack(spacing: GaugeLook.gapSmall) {
                        Text("RPM \(Int(rpm))").font(.caption).monospacedDigit()
                        Slider(value: $rpm, in: 0...7000, step: 50)
                    }
                    .padding()
                    .background(.bar)
                }
            }
        }
        .navigationTitle("Gauge lab")
        .navigationBarTitleDisplayMode(.inline)
        .background(.black)
        .preferredColorScheme(.dark)
    }

    private func gauge(_ style: GaugeStyle, _ finish: GaugeFinish, _ sensor: Sensor, _ value: Double) -> some View {
        let units = unitSettings.units
        let reading = GaugeReading(sensor: sensor, text: sensor.text(for: value, units: units), value: value,
                                   range: scanner.range(for: .sensor(sensor)), units: units)
        return StyledGauge(style: style, finish: finish, reading: reading)
    }
}

#Preview {
    NavigationStack { GaugeLabView(scanner: BluetoothScanner()) }
}
#endif
