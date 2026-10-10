import SwiftUI

/// Shown when the car's VIN is new. If there are cars created by hand (no VIN yet), it first asks whether it is one of them;
/// otherwise, or after "New car", it asks for make and model. The VIN itself is not shown.
struct CarInfoView: View {
    let scanner: BluetoothScanner
    @State private var newCar = false

    var body: some View {
        let unlinked = scanner.profiles.all.filter { $0.vin == nil }
        NavigationStack {
            if unlinked.isEmpty || newCar {
                MakeModelForm(title: "Which car is this?") { scanner.saveCar(make: $0, model: $1) }
            } else {
                Form {
                    Section("Is it one of these?") {
                        ForEach(unlinked) { car in
                            Button(car.name) { scanner.linkCar(car.id) }
                        }
                    }
                    Button("New car") { newCar = true }
                }
                .navigationTitle("Which car is this?")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
    }
}

/// Make and model, and a Save button that stays off while either is blank.
struct MakeModelForm: View {
    let title: String
    let save: (_ make: String, _ model: String) -> Void
    @State private var make = ""
    @State private var model = ""

    var body: some View {
        Form {
            Section("New car") {
                TextField("Make", text: $make)
                TextField("Model", text: $model)
            }
            Button("Save") { save(make, model) }
                .disabled(make.isBlank || model.isBlank)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private extension String {
    var isBlank: Bool { trimmingCharacters(in: .whitespaces).isEmpty }
}

#Preview {
    CarInfoView(scanner: BluetoothScanner())
}
