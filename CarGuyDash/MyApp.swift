import SwiftUI

@main struct MyApp: App {
    @State private var scanner = BluetoothScanner()

    var body: some Scene {
        WindowGroup {
            ContentView(scanner: scanner)
        }
    }
}
