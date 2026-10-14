import SwiftUI

/// Settings → Gauges: one car's gauges drawn as on the gauges page, each with a fixed sample value (the middle of its normal range).
/// Tapping a gauge opens a short sheet (sensor, style, look, remove); "+" adds one at the end. Saved on every change.
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

    private static let sheetHeight: CGFloat = 300

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
                            ForEach(GaugeSource.menuOrder, id: \.self) { Text($0.name) }
                        }
                        Picker("Style", selection: layout.slots[index].style) {
                            ForEach(GaugeStyle.allCases, id: \.self) { Text($0.rawValue) }
                        }
                        Picker("Look", selection: layout.slots[index].look) {
                            ForEach(GaugeFinish.allCases, id: \.self) { Text($0.title) }
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

    /// The gauge at a sample value from this car's range: RPM the middle of its normal band (3000 by default),
    /// the others their target (coolant 95 °C by default) or, without one, the middle of the scale. No live data.
    private func gauge(_ slot: GaugeSlot) -> some View {
        let source = slot.source
        let range = profiles.profile(id: carID)?.range(for: source) ?? .standard(for: source)
        let value = range.rpm.map { ($0.normalLow + $0.normalHigh) / 2 } ?? range.target ?? (range.min + range.max) / 2
        let reading = GaugeReading(sensor: source.sensor, text: source.sensor.text(for: value, units: units), value: value,
                                   range: range, units: units, name: source.name)
        return StyledGauge(style: slot.style, finish: slot.look, reading: reading)
    }
}

/// Settings → Sensor ranges: every sensor and the Boost of one car, each opening its range editor.
struct SensorRangesView: View {
    let units: Units
    let profiles: CarProfiles
    let carID: UUID

    var body: some View {
        List(GaugeSource.menuOrder, id: \.self) { source in
            NavigationLink(source.name) { SensorRangeEditor(source: source, units: units, profiles: profiles, carID: carID) }
        }
        .navigationTitle("Sensor ranges")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One source's range in one car, typed in the chosen units. Save checks the order and converts back to the internal unit;
/// an invalid range is not saved and the reason shows below the buttons.
/// RPM: min, normal low, normal high, redline, max. Every other source: min, target (may be left empty = all green), max.
struct SensorRangeEditor: View {
    let source: GaugeSource
    let units: Units
    let profiles: CarProfiles
    let carID: UUID
    /// The fields as typed, in the order of `titles`.
    @State private var texts: [String]
    @State private var message: String?
    @State private var messageIsProblem = false

    private var isRPM: Bool { source == .sensor(.rpm) }
    private var titles: [String] { isRPM ? ["Min", "Normal low", "Normal high", "Redline", "Max"] : ["Min", "Target", "Max"] }

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
                ForEach(titles.indices, id: \.self) { index in
                    LabeledContent(titles[index]) {
                        // Not the decimal pad: it has no minus key (Boost and temperatures go below zero).
                        TextField(!isRPM && index == 1 ? "None" : titles[index], text: $texts[index])
                            .keyboardType(.numbersAndPunctuation)
                            .multilineTextAlignment(.trailing)
                    }
                }
            } header: {
                if !unit.isEmpty { Text("In \(unit)") }
            } footer: {
                if !isRPM { Text("Leave Target empty for all green.") }
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
        let trimmed = texts.map { $0.trimmingCharacters(in: .whitespaces) }
        let values = trimmed.map { try? Double($0, format: .number) }
        let typed: GaugeRange
        if isRPM {
            let numbers = values.compactMap { $0 }
            guard numbers.count == 5 else { return show("Every field needs a number.", problem: true) }
            typed = GaugeRange(min: numbers[0], max: numbers[4],
                               rpm: RPMZones(normalLow: numbers[1], normalHigh: numbers[2], redline: numbers[3]))
        } else {
            // Only the target may be left empty.
            guard let min = values[0], let max = values[2], values[1] != nil || trimmed[1].isEmpty else {
                return show("Min and max need a number; target a number or nothing.", problem: true)
            }
            typed = GaugeRange(min: min, max: max, target: values[1])
        }
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

    /// The car's range in the chosen units (the default one if the car was deleted meanwhile); no target = an empty field.
    /// Fitted to the source, so RPM always has its zones and nothing else does: the fields match `titles`.
    private static func texts(for source: GaugeSource, _ units: Units, _ car: CarProfile?) -> [String] {
        let range = (car?.range(for: source) ?? .standard(for: source)).fitted(to: source).converted(for: source.sensor, units)
        let values: [Double?] = if let rpm = range.rpm {
            [range.min, rpm.normalLow, rpm.normalHigh, rpm.redline, range.max]
        } else {
            [range.min, range.target, range.max]
        }
        return values.map { $0?.formatted(.number.precision(.fractionLength(0...2)).grouping(.never)) ?? "" }
    }
}

extension CarProfiles {
    /// A two-way link to one field of one saved car, for the editors. A deleted car reads as `fallback` and ignores writes.
    func binding<Value>(_ id: UUID, _ field: WritableKeyPath<CarProfile, Value>, fallback: Value) -> Binding<Value> {
        Binding(get: { self.profile(id: id)?[keyPath: field] ?? fallback },
                set: { value in self.update(id) { $0[keyPath: field] = value } })
    }
}
