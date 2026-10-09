import SwiftUI

/// Shown when the car's VIN is new: asks for make and model. The VIN itself is not shown.
struct CarInfoView: View {
    let scanner: BluetoothScanner
    @State private var make = ""
    @State private var model = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("New car") {
                    TextField("Make", text: $make)
                    TextField("Model", text: $model)
                }
                Button("Save") { scanner.saveCar(make: make, model: model) }
                    .disabled(make.isBlank || model.isBlank)
            }
            .navigationTitle("Which car is this?")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private extension String {
    var isBlank: Bool { trimmingCharacters(in: .whitespaces).isEmpty }
}

#Preview {
    CarInfoView(scanner: BluetoothScanner())
}
