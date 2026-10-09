import SwiftUI

/// Settings: only the three unit choices for now (the rest comes in Phase 3).
struct SettingsView: View {
    @Bindable var unitSettings: UnitSettings

    var body: some View {
        Form {
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
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack { SettingsView(unitSettings: UnitSettings()) }
}
