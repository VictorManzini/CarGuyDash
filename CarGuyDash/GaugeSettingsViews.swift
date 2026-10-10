import SwiftUI

/// Settings → Gauges: one car's gauges drawn as on the gauges page, each with a fixed sample value (the middle of its normal range).
/// Tapping a gauge opens a short sheet (sensor, style, remove); "+" adds one at the end. Saved on every change.
struct GaugeLayoutEditor: View {
    let units: Units
    let profiles: CarProfiles
    let carID: UUID
    /// The gauge whose sheet is open. Debug: `-gaugeEditor.selected <index>` (0 = the first gauge) opens it at launch.
    @State private var selected: Int? = {
        #if DEBUG
        UserDefaults.standard.string(forKey: "gaugeEditor.selected").flatMap { Int($0) }
        #else
        nil
        #endif
    }()

    private static let sheetHeight: CGFloat = 280

    var body: some View {
        let layout = profiles.binding(carID, \.layout, fallback: .standard)
        let count = layout.wrappedValue.count
        GaugeGrid(count: count) { index in
            Button { selected = index } label: {
                gauge(layout.wrappedValue.slots[index])
                    .padding(GaugeLook.gapSmall)
                    .overlay {
                        if selected == index {
                            RoundedRectangle(cornerRadius: 12).strokeBorder(Color.accentColor, lineWidth: 2)
                        }
                    }
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
        .landscapeFullScreen()
        .navigationTitle("Gauges")
        .navigationBarTitleDisplayMode(.inline)
        .background(.black)
        .preferredColorScheme(.dark)
        .toolbar {
            if count < GaugeLayout.maxCount {
                Button {
                    layout.wrappedValue.count += 1
                    selected = count // the new last gauge (count is the value before adding)
                } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add gauge")
            }
        }
        .sheet(isPresented: Binding(get: { selected != nil }, set: { if !$0 { selected = nil } })) {
            if let index = selected, index < count {
                Form {
                    Section("Gauge \(index + 1)") {
                        Picker("Sensor", selection: layout.slots[index].source) {
                            ForEach(GaugeSource.all, id: \.self) { Text($0.name) }
                        }
                        Picker("Style", selection: layout.slots[index].style) {
                            ForEach(GaugeStyle.allCases, id: \.self) { Text($0.rawValue) }
                        }
                    }
                    Section {
                        Button("Remove gauge", role: .destructive) {
                            layout.wrappedValue.remove(at: index)
                            selected = nil
                        }
                        .disabled(count == 1)
                    }
                }
                // A normal modal sheet: the grid is blocked while it is open, and a tap outside it only closes it.
                .presentationDetents([.height(Self.sheetHeight)])
            }
        }
    }

    /// The gauge with the middle of this car's normal range for its source (RPM 3000, coolant ~97 °C by default). No live data.
    private func gauge(_ slot: GaugeSlot) -> some View {
        let source = slot.source
        let range = profiles.profile(id: carID)?.range(for: source) ?? .standard(for: source)
        let value = (range.normalLow + range.normalHigh) / 2
        let reading = GaugeReading(sensor: source.sensor, text: source.sensor.text(for: value, units: units), value: value,
                                   range: range, units: units, name: source.name)
        return StyledGauge(style: slot.style, reading: reading)
    }
}

/// Settings → Sensor ranges: every sensor and the Boost of one car, each opening its range editor.
struct SensorRangesView: View {
    let units: Units
    let profiles: CarProfiles
    let carID: UUID

    var body: some View {
        List(GaugeSource.all, id: \.self) { source in
            NavigationLink(source.name) { SensorRangeEditor(source: source, units: units, profiles: profiles, carID: carID) }
        }
        .navigationTitle("Sensor ranges")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One source's range in one car, typed in the chosen units. Save checks the order and converts back to the internal unit;
/// an invalid range is not saved and the reason shows below the buttons.
struct SensorRangeEditor: View {
    let source: GaugeSource
    let units: Units
    let profiles: CarProfiles
    let carID: UUID
    /// Min, normal low, normal high, redline, max, as typed.
    @State private var texts: [String]
    @State private var message: String?
    @State private var messageIsProblem = false

    private static let titles = ["Min", "Normal low", "Normal high", "Redline", "Max"]

    init(source: GaugeSource, units: Units, profiles: CarProfiles, carID: UUID) {
        self.source = source
        self.units = units
        self.profiles = profiles
        self.carID = carID
        _texts = State(initialValue: Self.texts(for: source, units, profiles.profile(id: carID)))
    }

    var body: some View {
        let unit = source.sensor.displayUnit(units)
        Form {
            Section {
                ForEach(Self.titles.indices, id: \.self) { index in
                    LabeledContent(Self.titles[index]) {
                        // Not the decimal pad: it has no minus key (Boost and temperatures go below zero).
                        TextField(Self.titles[index], text: $texts[index])
                            .keyboardType(.numbersAndPunctuation)
                            .multilineTextAlignment(.trailing)
                    }
                }
            } header: {
                if !unit.isEmpty { Text("In \(unit)") }
            }
            Section {
                Button("Save", action: save)
                Button("Reset to default", role: .destructive) {
                    profiles.update(carID) { $0.resetRange(source) }
                    texts = Self.texts(for: source, units, profiles.profile(id: carID))
                    show("Back to the default.", problem: false)
                }
            } footer: {
                if let message { Text(message).foregroundStyle(messageIsProblem ? .red : .secondary) }
            }
        }
        .navigationTitle(source.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func save() {
        let values = texts.compactMap { try? Double($0.trimmingCharacters(in: .whitespaces), format: .number) }
        guard values.count == 5 else { return show("Every field needs a number.", problem: true) }
        let typed = GaugeRange(min: values[0], max: values[4], normalLow: values[1], normalHigh: values[2], redline: values[3])
        var problem: String?
        profiles.update(carID) { problem = $0.saveRange(typed: typed, for: source, units: units) }
        if let problem {
            show(problem, problem: true)
        } else {
            show("Saved.", problem: false)
        }
    }

    private func show(_ text: String, problem: Bool) {
        message = text
        messageIsProblem = problem
    }

    /// The car's range in the chosen units (the default one if the car was deleted meanwhile).
    private static func texts(for source: GaugeSource, _ units: Units, _ car: CarProfile?) -> [String] {
        let range = (car?.range(for: source) ?? .standard(for: source)).converted(for: source.sensor, units)
        return [range.min, range.normalLow, range.normalHigh, range.redline, range.max]
            .map { $0.formatted(.number.precision(.fractionLength(0...2)).grouping(.never)) }
    }
}

extension CarProfiles {
    /// A two-way link to one field of one saved car, for the editors. A deleted car reads as `fallback` and ignores writes.
    func binding<Value>(_ id: UUID, _ field: WritableKeyPath<CarProfile, Value>, fallback: Value) -> Binding<Value> {
        Binding(get: { self.profile(id: id)?[keyPath: field] ?? fallback },
                set: { value in self.update(id) { $0[keyPath: field] = value } })
    }
}
