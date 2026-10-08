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
            .disabled(!scanner.isReady || scanner.isTesting || scanner.isPolling)

            HStack {
                Button("Start") { scanner.startPolling() }
                    .disabled(!scanner.isReady || scanner.isTesting || scanner.isPolling)
                Button("Stop") { scanner.stopPolling() }
                    .disabled(!scanner.isPolling)
            }

            #if DEBUG
            // Redraws twice a second, so a value turns "N/A" even when nothing new arrives.
            TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                VStack(alignment: .leading) {
                    ForEach(BluetoothScanner.polledSensors, id: \.self) { sensor in
                        Text("\(sensor.name): \(Self.text(scanner.liveData.value(for: sensor), sensor.unit))")
                    }
                }
                .font(.caption.monospaced())
            }
            #endif

            #if DEBUG
            Button("Simulated adapter") { Task { await scanner.useSimulatedAdapter() } }
                .disabled(scanner.state != .searching && scanner.state != .bluetoothOff)
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

    private static func text(_ value: Double?, _ unit: String) -> String {
        guard let value else { return "N/A" }
        return "\(value.formatted(.number.precision(.fractionLength(0...1)))) \(unit)"
    }
}

#Preview {
    ContentView(scanner: BluetoothScanner())
}
