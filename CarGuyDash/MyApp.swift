import SwiftUI

@main struct MyApp: App {
    @State private var scanner = BluetoothScanner()

    var body: some Scene {
        WindowGroup {
            NavigationStack { DashboardView(scanner: scanner) }
                // The screen stays on only while polling.
                .onChange(of: scanner.isPolling, initial: true) { UIApplication.shared.isIdleTimerDisabled = scanner.isPolling }
        }
    }
}
