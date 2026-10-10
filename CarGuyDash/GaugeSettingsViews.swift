import SwiftUI

/// Settings → Gauges: how many gauges (1 to 6) and, for each, the sensor and the style. Saved on every change.
struct GaugeLayoutEditor: View {
    @Bindable var settings: GaugeLayoutSettings

    var body: some View {
        Form {
            Stepper("Gauges: \(settings.layout.count)", value: $settings.layout.count, in: 1...GaugeLayout.maxCount)
            ForEach(settings.layout.visibleSlots.indices, id: \.self) { index in
                Section("Gauge \(index + 1)") {
                    Picker("Sensor", selection: $settings.layout.slots[index].source) {
                        ForEach(GaugeSource.all, id: \.self) { Text($0.name) }
                    }
                    Picker("Style", selection: $settings.layout.slots[index].style) {
                        ForEach(GaugeStyle.allCases, id: \.self) { Text($0.rawValue) }
                    }
                }
            }
        }
        .navigationTitle("Gauges")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Settings → Sensor ranges: every sensor and the Boost, each opening its range editor.
struct SensorRangesView: View {
    let units: Units
    @State private var ranges = GaugeRangeSettings()

    var body: some View {
        List(GaugeSource.all, id: \.self) { source in
            NavigationLink(source.name) { SensorRangeEditor(source: source, units: units, ranges: ranges) }
        }
        .navigationTitle("Sensor ranges")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One source's range, typed in the chosen units. Save checks the order and converts back to the internal unit;
/// an invalid range is not saved and the reason shows below the buttons.
struct SensorRangeEditor: View {
    let source: GaugeSource
    let units: Units
    let ranges: GaugeRangeSettings
    /// Min, normal low, normal high, redline, max, as typed.
    @State private var texts: [String]
    @State private var message: String?
    @State private var messageIsProblem = false

    private static let titles = ["Min", "Normal low", "Normal high", "Redline", "Max"]

    init(source: GaugeSource, units: Units, ranges: GaugeRangeSettings) {
        self.source = source
        self.units = units
        self.ranges = ranges
        _texts = State(initialValue: Self.texts(for: ranges.range(for: source).converted(for: source.sensor, units)))
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
                    ranges.reset(source)
                    texts = Self.texts(for: ranges.range(for: source).converted(for: source.sensor, units))
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
        if let problem = ranges.save(typed: typed, for: source, units: units) {
            show(problem, problem: true)
        } else {
            show("Saved.", problem: false)
        }
    }

    private func show(_ text: String, problem: Bool) {
        message = text
        messageIsProblem = problem
    }

    private static func texts(for range: GaugeRange) -> [String] {
        [range.min, range.normalLow, range.normalHigh, range.redline, range.max]
            .map { $0.formatted(.number.precision(.fractionLength(0...2)).grouping(.never)) }
    }
}
