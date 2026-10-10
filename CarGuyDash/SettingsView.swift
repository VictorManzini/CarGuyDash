import SwiftUI

/// Settings: the three unit choices, the gauge layout and the sensor ranges.
struct SettingsView: View {
    @Bindable var unitSettings: UnitSettings
    let gaugeLayout: GaugeLayoutSettings

    var body: some View {
        Form {
            Section("Units") {
                Picker("Temperature", selection: $unitSettings.units.temperature) {
                    ForEach(TemperatureUnit.allCases, id: \.self) { Text($0.rawValue) }
                }
                Picker("Pressure", selection: $unitSettings.units.pressure) {
                    ForEach(PressureUnit.allCases, id: \.self) { Text($0.rawValue) }
                }
                Picker("Speed", selection: $unitSettings.units.speed) {
                    ForEach(SpeedUnit.allCases, id: \.self) { Text($0.rawValue) }
                }
            }
            Section {
                NavigationLink("Gauges") { GaugeLayoutEditor(settings: gaugeLayout) }
                NavigationLink("Sensor ranges") { SensorRangesView(units: unitSettings.units) }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack { SettingsView(unitSettings: UnitSettings(), gaugeLayout: GaugeLayoutSettings()) }
}
