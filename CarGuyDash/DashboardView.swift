import SwiftUI

/// Gauges, numbers only: RPM on top, the other polled sensors in a 2-column grid.
struct DashboardView: View {
    let scanner: BluetoothScanner

    var body: some View {
        // Redraws twice a second, so a value turns "N/A" even when nothing new arrives.
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            ScrollView {
                VStack(spacing: 12) {
                    Text(scanner.state.rawValue).font(.caption).foregroundStyle(.secondary)
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
        .navigationTitle("Dashboard")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            NavigationLink("Tests") { ContentView(scanner: scanner) }
        }
    }

    /// Big value, small unit and name. No value: "N/A" in grey.
    private func block(_ sensor: Sensor, valueSize: CGFloat) -> some View {
        let value = scanner.liveData.value(for: sensor)
        return VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(sensor.text(for: value))
                    .font(.system(size: valueSize, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(value == nil ? .secondary : .primary)
                if value != nil {
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
