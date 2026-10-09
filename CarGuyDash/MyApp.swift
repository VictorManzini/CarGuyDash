import SwiftUI

@main struct MyApp: App {
    @State private var scanner = BluetoothScanner()
    @State private var unitSettings = UnitSettings()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            NavigationStack { DashboardView(scanner: scanner, unitSettings: unitSettings) }
                // The screen stays on only while polling.
                // .inactive is only the moment in between (e.g. Control Center), so it is ignored.
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { scanner.setAppPhase(.active) }
                    if phase == .background { scanner.setAppPhase(.background) }
                }
                .onChange(of: scanner.isPolling, initial: true) { UIApplication.shared.isIdleTimerDisabled = scanner.isPolling }
        }
    }
}
