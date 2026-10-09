import SwiftUI

/// Gauges, numbers only: RPM on top, the other polled sensors in a 2-column grid.
struct DashboardView: View {
    let scanner: BluetoothScanner

    var body: some View {
        // Redraws twice a second, so a value turns "N/A" even when nothing new arrives.
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            ScrollView {
                VStack(spacing: 12) {
                    Text("\(scanner.carName) · \(scanner.state.rawValue)").font(.caption).foregroundStyle(.secondary)
                    block(.rpm, valueSize: 96)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(BluetoothScanner.polledSensors.filter { $0 != .rpm }, id: \.self) { sensor in
                            block(sensor, valueSize: 56)
                        }
                    }
                }
                .padding()
            }
        }
        // Swiping the screen down closes it without saving: "Unknown car" until the next connection.
        .sheet(isPresented: Binding(get: { scanner.needsCarInfo }, set: { if !$0 { scanner.skipCarInfo() } })) {
            CarInfoView(scanner: scanner)
        }
        .navigationTitle("Dashboard")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if scanner.state == .disconnected {
                    Button("Connect") { scanner.connect() }
                } else {
                    Button("Disconnect") { scanner.disconnect() }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink("Tests") { ContentView(scanner: scanner) }
            }
        }
    }

    /// Big value, small unit and name. "Stand By" or "N/A" (no number) in grey, without the unit.
    private func block(_ sensor: Sensor, valueSize: CGFloat) -> some View {
        let value = scanner.liveData.value(for: sensor)
        let hasNumber = scanner.state == .ready && value != nil
        let text = gaugeText(for: sensor, state: scanner.state, value: value)
        // "Stand By" is a long word, so it gets a smaller size than a number.
        let size = text == "Stand By" ? valueSize * 0.55 : valueSize
        return VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(text)
                    .font(.system(size: size, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(hasNumber ? .primary : .secondary)
                if hasNumber {
                    Text(sensor.unit).font(.headline).foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            Text(sensor.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.fill.tertiary, in: .rect(cornerRadius: 12))
    }
}

#Preview {
    NavigationStack { DashboardView(scanner: BluetoothScanner()) }
}
