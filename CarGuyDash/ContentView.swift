import SwiftUI
import UIKit

/// In-car test screen: test buttons, copy/share, and the scrolling log.
struct ContentView: View {
    let scanner: BluetoothScanner

    var body: some View {
        VStack {
            HStack {
                Button("Test A") { Task { await scanner.runTestA() } }
                Button("Test B") { Task { await scanner.runTestB() } }
            }
            .disabled(!scanner.isReady || scanner.isTesting)

            #if DEBUG
            Button("Simulated adapter") { scanner.useSimulatedAdapter() }
                .disabled(scanner.isReady)
            #endif

            HStack {
                Button("Copy") { UIPasteboard.general.string = scanner.log.joined(separator: "\n") }
                ShareLink("Share", item: scanner.logFileURL)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading) {
                        ForEach(scanner.log.indices, id: \.self) { index in
                            Text(scanner.log[index]).font(.caption.monospaced()).id(index)
                        }
                    }
                }
                .onChange(of: scanner.log.count) { proxy.scrollTo(scanner.log.count - 1, anchor: .bottom) }
            }
        }
        .buttonStyle(.bordered)
        .padding()
    }
}

#Preview {
    ContentView(scanner: BluetoothScanner())
}
