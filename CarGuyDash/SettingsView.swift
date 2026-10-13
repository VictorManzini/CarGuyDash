import SwiftUI

/// Settings: the three unit choices (the owner's, shared by every car), the active car's gauges and ranges, and the cars.
struct SettingsView: View {
    @Bindable var unitSettings: UnitSettings
    let scanner: BluetoothScanner

    var body: some View {
        let profiles = scanner.profiles
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
                if let car = profiles.active {
                    NavigationLink("Gauges") { GaugeLayoutEditor(units: unitSettings.units, profiles: profiles, carID: car.id) }
                    NavigationLink("Sensor ranges") { SensorRangesView(units: unitSettings.units, profiles: profiles, carID: car.id) }
                }
                NavigationLink("Cars") { CarsView(scanner: scanner, units: unitSettings.units) }
            } header: {
                Text(profiles.active.map { "Active car: \($0.name)" } ?? "Car")
            } footer: {
                if profiles.active == nil { Text("Gauges and sensor ranges belong to a car. Add one in Cars.") }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Settings → Cars: every saved car, the active one ticked. The VIN shows only its last 4 characters.
struct CarsView: View {
    let scanner: BluetoothScanner
    let units: Units
    @State private var adding = false

    var body: some View {
        let profiles = scanner.profiles
        List(profiles.all) { car in
            NavigationLink { CarDetailView(scanner: scanner, units: units, carID: car.id) } label: {
                HStack {
                    VStack(alignment: .leading) {
                        Text(car.name)
                        Text(car.vinLabel).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if car.id == profiles.active?.id {
                        Image(systemName: "checkmark").foregroundStyle(.tint).accessibilityLabel("Active")
                    }
                }
            }
        }
        .overlay { if profiles.all.isEmpty { ContentUnavailableView("No cars yet", systemImage: "car") } }
        .toolbar { Button("Add car") { adding = true } }
        .sheet(isPresented: $adding) {
            NavigationStack {
                MakeModelForm(title: "Add car") { make, model in
                    profiles.add(make: make, model: model)
                    adding = false
                }
            }
        }
        .navigationTitle("Cars")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One car: make and model, its gauges and ranges, "Use this car" and Delete.
struct CarDetailView: View {
    let scanner: BluetoothScanner
    let units: Units
    let carID: UUID
    @State private var confirmingDelete = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let profiles = scanner.profiles
        let isActive = profiles.active?.id == carID
        let isConnected = scanner.connectedCarID == carID
        // Connected to a known car: its VIN decides the active car, so "Use this car" waits for Disconnect.
        let connectedToAnother = scanner.connectedCarID != nil && !isConnected
        Form {
            Section {
                TextField("Make", text: profiles.binding(carID, \.make, fallback: ""))
                TextField("Model", text: profiles.binding(carID, \.model, fallback: ""))
                LabeledContent("VIN", value: profiles.profile(id: carID)?.vinLabel ?? "")
            }
            Section {
                NavigationLink("Gauges") { GaugeLayoutEditor(units: units, profiles: profiles, carID: carID) }
                NavigationLink("Sensor ranges") { SensorRangesView(units: units, profiles: profiles, carID: carID) }
            }
            Section {
                Button("Use this car") { profiles.use(carID) }
                    .disabled(isActive || connectedToAnother)
            } footer: {
                if isActive {
                    Text("This is the active car.")
                } else if connectedToAnother {
                    Text("Another car is connected. Disconnect to use this one.")
                }
            }
            Section {
                Button("Delete car", role: .destructive) { confirmingDelete = true }
                    .disabled(isConnected)
            } footer: {
                if isConnected { Text("Connected now, so it can't be deleted.") }
            }
        }
        .confirmationDialog("Delete this car?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete car", role: .destructive) {
                scanner.deleteCar(carID)
                dismiss()
            }
        } message: {
            Text("Its gauges and sensor ranges are deleted too.")
        }
        .navigationTitle(profiles.profile(id: carID)?.name ?? "Car")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack { SettingsView(unitSettings: UnitSettings(), scanner: BluetoothScanner()) }
}
