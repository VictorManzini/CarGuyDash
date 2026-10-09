#if DEBUG
import SwiftUI

/// Debug only: the four gauge styles side by side, to check the colors without the car.
/// Sensor and value are kept in UserDefaults, so launch arguments can set them for screenshots:
/// `-openGaugePreview YES -gaugePreview.sensor 05 -gaugePreview.value 95 -gaugePreview.state "Stand By"`.
struct GaugePreviewView: View {
    @AppStorage("gaugePreview.sensor") private var sensor = Sensor.coolantTemp
    @AppStorage("gaugePreview.value") private var value = 95.0
    /// "Stand By" or "N/A" in place of the number; empty = show the value.
    @AppStorage("gaugePreview.state") private var state = ""
    @State private var ranges = GaugeRangeSettings()
    @State private var unitSettings = UnitSettings()

    var body: some View {
        let range = ranges.range(for: sensor)
        let text = state.isEmpty ? sensor.text(for: value, units: unitSettings.units) : state
        let reading = GaugeReading(sensor: sensor, text: text, value: value, range: range, units: unitSettings.units)
        ScrollView {
            VStack(spacing: 24) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 16)], spacing: 24) {
                    AnalogGauge(reading: reading).frame(height: 210)
                    DigitalGauge(reading: reading).frame(height: 210)
                    BarGauge(reading: reading).frame(height: 210)
                    ArcGauge(reading: reading).frame(height: 210)
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
        .onChange(of: sensor) { value = ranges.range(for: sensor).min }
        .navigationTitle("Gauge preview")
        .navigationBarTitleDisplayMode(.inline)
        .background(.black)
        .preferredColorScheme(.dark)
    }
}

#Preview {
    NavigationStack { GaugePreviewView() }
}
#endif
