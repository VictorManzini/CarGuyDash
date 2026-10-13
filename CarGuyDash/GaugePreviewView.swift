#if DEBUG
import SwiftUI

/// Debug only: the four gauge styles in each look (A, B, C), to check the colors without the car.
/// Sensor and value are kept in UserDefaults, so launch arguments can set them for screenshots:
/// `-openGaugePreview YES -gaugePreview.sensor 05 -gaugePreview.value 95 -gaugePreview.state "Stand By"`.
struct GaugePreviewView: View {
    /// The ranges come from the active car.
    let scanner: BluetoothScanner
    @AppStorage("gaugePreview.sensor") private var sensor = Sensor.coolantTemp
    @AppStorage("gaugePreview.value") private var value = 95.0
    /// "Stand By" or "N/A" in place of the number; empty = show the value.
    @AppStorage("gaugePreview.state") private var state = ""
    @State private var unitSettings = UnitSettings()

    var body: some View {
        let range = scanner.range(for: .sensor(sensor))
        let text = state.isEmpty ? sensor.text(for: value, units: unitSettings.units) : state
        let reading = GaugeReading(sensor: sensor, text: text, value: value, range: range, units: unitSettings.units)
        ScrollView {
            VStack(spacing: GaugeLook.gapLarge) {
                ForEach(GaugeFinish.allCases, id: \.self) { finish in
                    VStack(alignment: .leading, spacing: GaugeLook.gap) {
                        Text(finish.title).font(.headline)
                        HStack(spacing: GaugeLook.gap) {
                            ForEach(GaugeStyle.allCases, id: \.self) { StyledGauge(style: $0, finish: finish, reading: reading) }
                        }
                        .frame(height: 150)
                    }
                }

                Picker("Sensor", selection: $sensor) {
                    ForEach(Sensor.allCases, id: \.self) { Text($0.name) }
                }
                Slider(value: $value, in: range.min...range.max)
                HStack {
                    Button("Value") { state = "" }
                    Button("Stand By") { state = "Stand By" }
                    Button("N/A") { state = "N/A" }
                }
                .buttonStyle(.bordered)
            }
            .padding()
        }
        .onChange(of: sensor) { value = scanner.range(for: .sensor(sensor)).min }
        .navigationTitle("Gauge preview")
        .navigationBarTitleDisplayMode(.inline)
        .background(.black)
        .preferredColorScheme(.dark)
    }
}

#Preview {
    NavigationStack { GaugePreviewView(scanner: BluetoothScanner()) }
}
#endif
