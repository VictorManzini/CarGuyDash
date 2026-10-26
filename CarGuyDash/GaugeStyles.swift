import SwiftUI

/// What every gauge style gets: the sensor, the text from `gaugeText` (a number, "Stand By" or "N/A"),
/// the value in the internal unit (°C, kPa, km/h), the sensor's range and the chosen units.
/// The styles are drawn for a dark background.
nonisolated struct GaugeReading {
    let sensor: Sensor
    let text: String
    let value: Double?
    let range: GaugeRange
    let units: Units
    /// Label under the gauge when it is not the sensor's name ("Boost" for the manifold pressure).
    var name: String? = nil

    /// The value to draw; nil while the text is "Stand By" or "N/A" (no needle movement, no fill).
    var number: Double? { text == "Stand By" || text == "N/A" ? nil : value }
    /// Red on the Digital: from RPM's redline, or exactly at max for every other source (above the target is still fine).
    var isRedline: Bool { number.map { $0 >= range.rpm?.redline ?? range.max } ?? false }
}

// MARK: - Shared look

/// The one set of measures, colors and motion every style uses, so the four look like one family.
enum GaugeLook {
    /// Spacing scale: 4 / 8 / 16.
    static let gapSmall: CGFloat = 4
    static let gap: CGFloat = 8
    static let gapLarge: CGFloat = 16

    /// Numbers. Secondary: units, names, Stand By / N/A (about 7:1 on black).
    static let primary = Color(white: 0.94)
    static let secondary = Color(white: 0.62)
    /// The empty part of a bar or arc track, and an unlit LED block.
    static let unlit = Color(white: 0.1)

    /// The dial arc of the analog and arc styles: 260°, open at the bottom, starting lower left.
    static let arcStart = 140.0
    static let arcSweep = 260.0

    /// Critically damped: follows the value smoothly, never overshoots.
    static let motion = Animation.spring(response: 0.3, dampingFraction: 1)
    /// RPM changes fast, so its needle and fill only cover the gap to the next reading: a short linear move.
    /// RPM arrives about every 0.2 s (every other request, ~100 ms each); capped at 0.12 s so it never trails the engine.
    static let rpmMotion = Animation.linear(duration: 0.12)

    static func motion(for sensor: Sensor) -> Animation { sensor == .rpm ? rpmMotion : motion }

    /// The value text size every Digital, Bar and Arc gauge of one grid shares, from the cell's size:
    /// a fifth of the cell's smaller side once the name line is taken off.
    static func valueSize(cell: CGSize) -> CGFloat { max(0, min(cell.width, cell.height - nameLine)) * 0.2 }

    /// The name above each gauge: 13 pt text (about 15.5 pt tall) plus its gap, with 2 pt to spare.
    static let nameLine: CGFloat = 26

    /// In a grid the Digital's number may outgrow the shared size, up to this many times it.
    static let digitalGrowth: CGFloat = 1.5

    /// The Digital's number size in a grid: its own preferred size, never below the shared size, never above `digitalGrowth` times it.
    static func digitalSize(preferred: CGFloat, grid: CGFloat) -> CGFloat { max(grid, min(preferred, grid * digitalGrowth)) }
}

private struct GaugeValueSizeKey: EnvironmentKey {
    static let defaultValue: CGFloat? = nil
}

extension EnvironmentValues {
    /// Set by `GaugeGrid` so every value text in it has one size; nil elsewhere (each style picks its own).
    var gaugeValueSize: CGFloat? {
        get { self[GaugeValueSizeKey.self] }
        set { self[GaugeValueSizeKey.self] = newValue }
    }
}

extension Color {
    init(rgb: (r: Double, g: Double, b: Double)) {
        self.init(red: rgb.r / 255, green: rgb.g / 255, blue: rgb.b / 255)
    }
}

extension GaugeColor {
    var color: Color { Color(rgb: rgb) }
}

extension GaugeRange {
    /// The fixed gradient blue → green → yellow → orange → red from the color stops, squeezed into `length`
    /// of the gradient's run (1 = all of it; an arc of 260° inside a 360° conic gradient = 260 / 360).
    func gradient(length: Double = 1) -> Gradient {
        Gradient(stops: stops.map { Gradient.Stop(color: $0.color.color, location: $0.at * length) })
    }

    /// The gradient's color at a place on the scale (0 = min, 1 = max): the color of one LED block of the race dash.
    func color(atFraction fraction: Double) -> Color { Color(rgb: rgb(at: min + (max - min) * fraction)) }
}

// MARK: - Looks

/// What one look changes: the materials, the ink and the analog dial's proportions (the values tried in the Gauge lab).
private struct FinishSpec {
    /// Bezel thickness as a fraction of the radius; its color at the top (lit) and at the bottom.
    let bezel: Double
    let bezelTop: Color
    let bezelBottom: Color
    let faceCenter: Color
    let faceEdge: Color
    /// Ticks and numbers.
    let ink: Color
    /// Analog numbers and zone bands, as fractions of the face radius.
    let numberSize: Double
    let zoneWidth: Double
    let needle: Color
    /// The glass reflection's opacity at its brightest; `dome` adds a curved highlight like a domed lens.
    let glass: Double
    let dome: Bool
}

extension GaugeFinish {
    /// A: matte black face, thin satin-chrome bezel, thin white ink, orange-red needle.
    /// B: big condensed numbers, high contrast, LED blocks, shift lights on RPM.
    /// C: deep black face, thick dark-metal bezel, backlit white ink, red peak marker, domed glass.
    fileprivate var spec: FinishSpec {
        switch self {
        case .oem:
            FinishSpec(bezel: 0.05, bezelTop: Color(white: 0.82), bezelBottom: Color(white: 0.3),
                       faceCenter: Color(white: 0.085), faceEdge: Color(white: 0.045), ink: Color(white: 0.92),
                       numberSize: 0.13, zoneWidth: 0.045, needle: Color(red: 1, green: 0.33, blue: 0.1), glass: 0.05, dome: false)
        case .race:
            FinishSpec(bezel: 0.035, bezelTop: Color(white: 0.42), bezelBottom: Color(white: 0.1),
                       faceCenter: Color(white: 0.03), faceEdge: .black, ink: .white,
                       numberSize: 0.2, zoneWidth: 0.06, needle: GaugeColor.red.color, glass: 0.03, dome: false)
        case .aftermarket:
            FinishSpec(bezel: 0.11, bezelTop: Color(white: 0.46), bezelBottom: Color(white: 0.06),
                       faceCenter: Color(white: 0.045), faceEdge: .black, ink: Color(white: 0.96),
                       numberSize: 0.12, zoneWidth: 0.03, needle: Color(red: 1, green: 0.27, blue: 0.12), glass: 0.1, dome: true)
        }
    }

    /// DIN numbers with fixed-width digits: Condensed for the race dash, Alternate for the others. Fixed size (no Dynamic Type):
    /// every size is measured from the gauge.
    func font(_ size: CGFloat) -> Font {
        .custom(self == .race ? "DINCondensed-Bold" : "DINAlternate-Bold", fixedSize: size).monospacedDigit()
    }
}

// MARK: - Shared drawing

/// A round gauge's geometry: center, radius and the 260° scale.
private struct Dial {
    let center: CGPoint
    let r: CGFloat

    init(_ size: CGSize) {
        center = CGPoint(x: size.width / 2, y: size.height / 2)
        r = min(size.width, size.height) / 2
    }

    func circle(_ radius: CGFloat, dy: CGFloat = 0) -> Path {
        Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius + dy, width: 2 * radius, height: 2 * radius))
    }

    func angle(_ fraction: Double) -> Double { Angle.degrees(GaugeLook.arcStart + GaugeLook.arcSweep * fraction).radians }

    func point(_ fraction: Double, _ radius: CGFloat) -> CGPoint {
        CGPoint(x: center.x + radius * cos(angle(fraction)), y: center.y + radius * sin(angle(fraction)))
    }

    func arc(_ from: Double, _ to: Double, radius: CGFloat) -> Path {
        var path = Path()
        path.addArc(center: center, radius: radius, startAngle: .radians(angle(from)), endAngle: .radians(angle(to)), clockwise: false)
        return path
    }
}

/// The zones painted on the analog scale for RPM, as fractions: blue below normalLow (when there is one), then GaugeRange's
/// stops past the normal band: yellow from normalHigh, orange from halfway to the redline, red from the redline to max.
/// None for the other sources: with a target they get the whole gradient instead (see `AnalogGauge.draw`).
private func zones(_ range: GaugeRange) -> [(from: Double, to: Double, color: Color)] {
    guard let rpm = range.rpm else { return [] }
    let orange = (rpm.normalHigh + rpm.redline) / 2
    var values: [(Double, Double, GaugeColor)] = rpm.normalLow > range.min ? [(range.min, rpm.normalLow, .blue)] : []
    values += [(rpm.normalHigh, orange, .yellow), (orange, rpm.redline, .orange), (rpm.redline, range.max, .red)]
    return values.map { (range.fraction($0.0), range.fraction($0.1), $0.2.color) }.filter { $0.from < $0.to }
}

/// Round bezel lit from the top with a darker bottom, then the face, recessed: a soft shadow inside the rim,
/// heavier at the top where the bezel blocks the light. Returns the face radius.
private func drawRoundHousing(_ spec: FinishSpec, _ d: Dial, in ctx: inout GraphicsContext) -> CGFloat {
    let r = d.r
    let top = CGPoint(x: d.center.x, y: d.center.y - r), bottom = CGPoint(x: d.center.x, y: d.center.y + r)
    ctx.fill(d.circle(r), with: .linearGradient(Gradient(colors: [spec.bezelTop, spec.bezelBottom]), startPoint: top, endPoint: bottom))
    // Inner chamfer, lit the other way, so the ring reads as raised.
    ctx.fill(d.circle(r * (1 - spec.bezel * 0.4)),
             with: .linearGradient(Gradient(colors: [spec.bezelBottom, spec.bezelTop.opacity(0.75)]), startPoint: top, endPoint: bottom))
    let faceR = r * (1 - spec.bezel)
    ctx.fill(d.circle(faceR), with: .radialGradient(Gradient(colors: [spec.faceCenter, spec.faceEdge]),
                                                     center: d.center, startRadius: 0, endRadius: faceR))
    ctx.drawLayer { layer in
        layer.clip(to: d.circle(faceR))
        layer.addFilter(.blur(radius: r * 0.035))
        var shade = Path(CGRect(x: d.center.x - 2 * r, y: d.center.y - 2 * r, width: 4 * r, height: 4 * r))
        shade.addPath(d.circle(faceR * 0.96, dy: r * 0.035))
        layer.fill(shade, with: .color(.black.opacity(0.85)), style: FillStyle(eoFill: true))
    }
    ctx.stroke(d.circle(faceR), with: .color(.black), lineWidth: max(1, r * 0.01))
    return faceR
}

/// A very faint reflection on the top half of the glass; a domed lens also gets a thin curved highlight.
private func drawGlass(_ spec: FinishSpec, clip: Path, top: CGFloat, middle: CGFloat, in ctx: inout GraphicsContext,
                       dome: Path, size: CGFloat) {
    ctx.drawLayer { layer in
        layer.clip(to: clip)
        let rect = clip.boundingRect
        // Soft edges: a sharp edge would read as a drawn line, not as light on glass.
        layer.addFilter(.blur(radius: size * 0.04))
        layer.fill(Path(ellipseIn: CGRect(x: rect.minX - rect.width * 0.05, y: top - rect.height * 0.3,
                                          width: rect.width * 1.1, height: middle - top + rect.height * 0.3)),
                   with: .linearGradient(Gradient(colors: [.white.opacity(spec.glass), .white.opacity(0)]),
                                         startPoint: CGPoint(x: rect.midX, y: top), endPoint: CGPoint(x: rect.midX, y: middle)))
        if spec.dome {
            layer.stroke(dome, with: .color(.white.opacity(spec.glass * 1.6)), style: StrokeStyle(lineWidth: size * 0.025, lineCap: .round))
        }
    }
}

/// A rectangular instrument's bezel and face (Bar and Digital). `side` sets the bezel thickness and the corners:
/// the Bar's width, so a Digital frame matches the Bar's in the same look and the same space.
private struct RectHousing {
    let outer: CGRect
    let face: CGRect
    let corner: CGFloat
    let side: CGFloat

    init(_ outer: CGRect, side: CGFloat, _ spec: FinishSpec) {
        let bezel = side / 2 * spec.bezel * 1.4
        self.outer = outer
        self.side = side
        face = outer.insetBy(dx: bezel, dy: bezel)
        corner = side * 0.14 - bezel
    }

    var facePath: Path { Path(roundedRect: face, cornerRadius: corner) }

    /// Bezel lit from the top, then the recessed face (same recipe as the round housing).
    func draw(_ spec: FinishSpec, in ctx: inout GraphicsContext) {
        ctx.fill(Path(roundedRect: outer, cornerRadius: side * 0.14),
                 with: .linearGradient(Gradient(colors: [spec.bezelTop, spec.bezelBottom]),
                                       startPoint: CGPoint(x: outer.midX, y: outer.minY), endPoint: CGPoint(x: outer.midX, y: outer.maxY)))
        ctx.fill(facePath, with: .linearGradient(Gradient(colors: [spec.faceCenter, spec.faceEdge]),
                                                 startPoint: CGPoint(x: face.midX, y: face.minY), endPoint: CGPoint(x: face.midX, y: face.maxY)))
        ctx.drawLayer { layer in
            layer.clip(to: facePath)
            layer.addFilter(.blur(radius: side * 0.03))
            var shade = Path(outer.insetBy(dx: -side, dy: -side))
            shade.addPath(Path(roundedRect: face.insetBy(dx: side * 0.02, dy: side * 0.02).offsetBy(dx: 0, dy: side * 0.03),
                               cornerRadius: corner))
            layer.fill(shade, with: .color(.black.opacity(0.85)), style: FillStyle(eoFill: true))
        }
    }
}

/// The glass of a round gauge, with the dome's highlight on the upper left.
private func drawRoundGlass(_ spec: FinishSpec, _ d: Dial, face f: CGFloat, in ctx: inout GraphicsContext) {
    var dome = Path()
    dome.addArc(center: d.center, radius: f * 0.86, startAngle: .degrees(205), endAngle: .degrees(250), clockwise: false)
    drawGlass(spec, clip: d.circle(f), top: d.center.y - f, middle: d.center.y, in: &ctx, dome: dome, size: f)
}

/// A Canvas whose `at` (where the value sits on the scale, 0...1) is animated: with `.animation(GaugeLook.motion(for:), value:)`
/// the needle, the fill and the LED blocks follow the value smoothly instead of jumping between readings.
private struct AnimatedCanvas: View, Animatable {
    var at: Double
    let draw: (inout GraphicsContext, CGSize, Double) -> Void

    var animatableData: Double {
        get { at }
        set { at = newValue }
    }

    var body: some View {
        Canvas { context, size in draw(&context, size, at) }
    }
}

/// Every style: the name on top, the gauge always `GaugeLook.gap` below it and sitting on the top of its space,
/// so names in one row line up whatever the styles.
private struct GaugeCell<Content: View>: View {
    let reading: GaugeReading
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: GaugeLook.gap) {
            Text((reading.name ?? reading.sensor.name).uppercased())
                .font(.system(size: 13, weight: .medium))
                .tracking(0.8) // small text: a little looser; tighter than before so long names stay big
                .foregroundStyle(GaugeLook.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}

/// Number and unit as one text in the look's DIN font, so they share one baseline and shrink together.
/// White, red from the redline (`isRedline`: RPM's redline, max for the others). "Stand By" / "N/A" replace both, in grey. Inside a `GaugeGrid` the grid's size wins over `preferredSize`,
/// except with `growsInGrid` (the Digital), which may grow up to `GaugeLook.digitalSize`.
private struct GaugeValue: View {
    let reading: GaugeReading
    let finish: GaugeFinish
    let preferredSize: CGFloat
    let growsInGrid: Bool
    @Environment(\.gaugeValueSize) private var gridSize

    init(reading: GaugeReading, finish: GaugeFinish, size: CGFloat, growsInGrid: Bool = false) {
        self.reading = reading
        self.finish = finish
        preferredSize = size
        self.growsInGrid = growsInGrid
    }

    var body: some View {
        let size = gridSize.map { growsInGrid ? GaugeLook.digitalSize(preferred: preferredSize, grid: $0) : $0 } ?? preferredSize
        Group {
            if reading.number == nil {
                Text(reading.text).font(.system(size: size * 0.5, weight: .semibold)).foregroundStyle(GaugeLook.secondary)
            } else {
                let unit = reading.sensor.displayUnit(reading.units)
                let number = Text(reading.text)
                    .font(finish.font(size))
                    .foregroundStyle(reading.isRedline ? GaugeColor.red.color : GaugeLook.primary)
                // Thin space between number and unit.
                let suffix = Text(unit.isEmpty ? "" : "\u{2009}" + unit).font(finish.font(size * 0.36)).foregroundStyle(GaugeLook.secondary)
                Text("\(number)\(suffix)")
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.4)
    }
}

/// The min and max of the scale in the chosen units, whole numbers, as drawn at both ends of the arc and the bar.
private func endLabel(_ value: Double) -> Text {
    Text(value.formatted(.number.precision(.fractionLength(0)).grouping(.never)))
}

// MARK: - Analog

/// The dial's numbers and ticks in the chosen units: a round step (1, 2 or 5 × 10ⁿ) between numbers,
/// every number on a major tick, minor ticks in between. Built from whole tick counts, so nothing drifts.
nonisolated struct DialScale {
    /// Distance between numbers.
    let step: Double
    /// 1000 when the numbers are written in thousands (RPM: "7" = 7000).
    let divisor: Double
    let ticks: [(value: Double, isMajor: Bool)]

    init(min: Double, max: Double) {
        let span = max - min
        guard span > 0 else { step = 1; divisor = 1; ticks = []; return }
        // At most 8 gaps between numbers.
        let raw = span / 8
        let power = pow(10, floor(log10(raw)))
        let mantissa = [1.0, 2, 5, 10].first { $0 * power >= raw * (1 - 1e-9) } ?? 10
        step = mantissa * power
        divisor = step >= 1000 ? 1000 : 1
        let perMajor = mantissa == 2 ? 4 : 5
        let minor = step / Double(perMajor)
        let first = Int((min / minor - 1e-9).rounded(.up)), last = Int((max / minor + 1e-9).rounded(.down))
        ticks = first <= last ? (first...last).map { (Double($0) * minor, $0 % perMajor == 0) } : []
    }

    func label(_ value: Double) -> String {
        let shown = value / divisor
        return String(format: "%g", abs(shown) < 1e-9 ? 0 : shown)
    }
}

/// A round dial in the slot's look: bezel lit from the top, recessed face, the zones on the scale's outer edge,
/// ticks with DIN numbers inside them, needle with a drop shadow and a black cap, glass on top.
/// Race dash on RPM: shift lights above the dial. Aftermarket: a red peak marker at the highest value seen.
struct AnalogGauge: View {
    let reading: GaugeReading
    let finish: GaugeFinish
    /// The highest value since the gauge appeared (aftermarket peak marker); starts again when the range changes (another sensor).
    @State private var peak: Double?

    var body: some View {
        GaugeCell(reading: reading) {
            VStack(spacing: GaugeLook.gap) {
                if finish == .race, reading.sensor == .rpm {
                    ShiftLights(range: reading.range, value: reading.number)
                }
                ZStack {
                    AnimatedCanvas(at: reading.range.fraction(reading.number ?? reading.range.min)) { context, size, at in
                        draw(&context, size, at: at)
                    }
                    .animation(GaugeLook.motion(for: reading.sensor), value: reading.number)
                    if reading.number == nil {
                        // Stand By / N/A: near-transparent grey layer + red text in the center (needle and cap hidden).
                        Circle().fill(.gray.opacity(0.35))
                        GeometryReader { geo in
                            Text(reading.text)
                                .font(.system(size: geo.size.width * 0.08, weight: .semibold))
                                .foregroundStyle(GaugeColor.red.color)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                }
                .aspectRatio(1, contentMode: .fit)
            }
        }
        .onChange(of: reading.number, initial: true) {
            if let number = reading.number { peak = max(peak ?? number, number) }
        }
        .onChange(of: reading.range) { peak = reading.number }
    }

    private func draw(_ ctx: inout GraphicsContext, _ size: CGSize, at: Double) {
        let spec = finish.spec, range = reading.range
        let d = Dial(size)
        let f = drawRoundHousing(spec, d, in: &ctx)

        // RPM: zones as solid bands on the scale's outer edge. A target: the same place gets the whole gradient, min to max,
        // turning with the scale like the Arc's (260° of a 360° conic gradient). No target: nothing (all green).
        for zone in zones(range) {
            ctx.stroke(d.arc(zone.from, zone.to, radius: f * 0.9), with: .color(zone.color), lineWidth: f * spec.zoneWidth)
        }
        if range.rpm == nil, range.target != nil {
            ctx.stroke(d.arc(0, 1, radius: f * 0.9),
                       with: .conicGradient(range.gradient(length: GaugeLook.arcSweep / 360), center: d.center,
                                            angle: .degrees(GaugeLook.arcStart)),
                       lineWidth: f * spec.zoneWidth)
        }

        // Ticks and numbers in the chosen units.
        let display = range.converted(for: reading.sensor, reading.units)
        let scale = DialScale(min: display.min, max: display.max)
        let span = display.max - display.min
        if span > 0 {
            for tick in scale.ticks {
                let fraction = (tick.value - display.min) / span
                var path = Path()
                path.move(to: d.point(fraction, f * 0.86))
                path.addLine(to: d.point(fraction, f * (tick.isMajor ? 0.74 : 0.8)))
                ctx.stroke(path, with: .color(spec.ink.opacity(tick.isMajor ? 1 : 0.6)), lineWidth: f * (tick.isMajor ? 0.022 : 0.01))
            }
            let majors = scale.ticks.filter(\.isMajor)
            // One size per look; only labels too long to keep apart (kPa: "-100") shrink.
            var fontSize = f * spec.numberSize
            let widest = majors.map { ctx.resolve(Text(scale.label($0.value)).font(finish.font(fontSize))).measure(in: size).width }.max() ?? 0
            if widest > f * 0.28 { fontSize *= f * 0.28 / widest }
            let labelRadius = f * (0.72 - spec.numberSize * 0.75)
            for tick in majors {
                ctx.draw(Text(scale.label(tick.value)).font(finish.font(fontSize)).foregroundStyle(spec.ink),
                         at: d.point((tick.value - display.min) / span, labelRadius))
            }
        }
        let unit = reading.sensor.displayUnit(reading.units)
        ctx.draw(Text(scale.divisor == 1000 ? "×1000 \(unit)" : unit).font(finish.font(f * 0.08)).foregroundStyle(spec.ink.opacity(0.6)),
                 at: CGPoint(x: d.center.x, y: d.center.y + f * 0.4))

        if reading.number != nil {
            if finish == .aftermarket, let peak, peak > range.min {
                var mark = Path()
                mark.move(to: d.point(range.fraction(peak), f * 0.94))
                mark.addLine(to: d.point(range.fraction(peak), f * 0.78))
                ctx.stroke(mark, with: .color(GaugeColor.red.color), style: StrokeStyle(lineWidth: f * 0.03, lineCap: .round))
            }

            // Needle with a soft drop shadow (depth, not a glow), then the black center cap.
            ctx.drawLayer { layer in
                layer.addFilter(.shadow(color: .black.opacity(0.7), radius: f * 0.02, x: 0, y: f * 0.02))
                var needle = Path()
                needle.move(to: CGPoint(x: -f * 0.16, y: -f * 0.028))
                needle.addLine(to: CGPoint(x: f * 0.84, y: -f * 0.006))
                needle.addLine(to: CGPoint(x: f * 0.84, y: f * 0.006))
                needle.addLine(to: CGPoint(x: -f * 0.16, y: f * 0.028))
                needle.closeSubpath()
                let place = CGAffineTransform(rotationAngle: d.angle(at))
                    .concatenating(CGAffineTransform(translationX: d.center.x, y: d.center.y))
                layer.fill(needle.applying(place), with: .color(spec.needle))
                layer.fill(d.circle(f * 0.085), with: .radialGradient(Gradient(colors: [Color(white: 0.2), .black]),
                                                                      center: CGPoint(x: d.center.x, y: d.center.y - f * 0.03),
                                                                      startRadius: 0, endRadius: f * 0.1))
            }
            ctx.stroke(d.circle(f * 0.085), with: .color(Color(white: 0.3)), lineWidth: max(0.5, f * 0.006))
        }

        drawRoundGlass(spec, d, face: f, in: &ctx)
    }
}

/// Race dash shift lights: 4 green, 3 yellow, 3 red, lighting up one by one from normalHigh to the redline;
/// all of them flash at the redline. All off without a value (Stand By, N/A).
private struct ShiftLights: View {
    let range: GaugeRange
    let value: Double?

    private static let colors: [GaugeColor] = [.green, .green, .green, .green, .yellow, .yellow, .yellow, .red, .red, .red]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.125)) { timeline in
            // Only RPM gets shift lights, and RPM always has zones; without them they would light only at max.
            let normalHigh = range.rpm?.normalHigh ?? range.max, redline = range.rpm?.redline ?? range.max
            let flashing = value.map { $0 >= redline } ?? false
            let flashOn = Int(timeline.date.timeIntervalSinceReferenceDate * 8) % 2 == 0
            let span = redline - normalHigh
            let lit = value.map { span > 0 ? Int((($0 - normalHigh) / span * 10).rounded(.down)) : 0 } ?? 0
            HStack(spacing: GaugeLook.gapSmall) {
                ForEach(Self.colors.indices, id: \.self) { index in
                    let on = flashing ? flashOn : index < lit
                    let color = Self.colors[index].color
                    Circle()
                        .fill(on ? color : color.opacity(0.13))
                        .overlay(Circle().strokeBorder(.black.opacity(0.7), lineWidth: 1))
                        .aspectRatio(1, contentMode: .fit)
                }
            }
            .frame(maxHeight: 18)
        }
    }
}

// MARK: - Digital

/// Big DIN number: white, red only from the redline (`isRedline`), centered in a rectangular frame in the slot's look
/// (bezel, recessed face, glass), with the Bar's bezel thickness and corners. The frame takes the whole width
/// and the round gauges' height (the smaller side), sitting on the bottom like the others.
struct DigitalGauge: View {
    let reading: GaugeReading
    let finish: GaugeFinish

    var body: some View {
        GaugeCell(reading: reading) {
            GeometryReader { geo in
                let spec = finish.spec
                // The Bar's width in this same space, so bezel and corners match it.
                let side = min(geo.size.width, geo.size.height * BarGauge.aspect)
                let size = CGSize(width: geo.size.width, height: min(geo.size.width, geo.size.height))
                let housing = RectHousing(CGRect(origin: .zero, size: size), side: side, spec)
                ZStack {
                    Canvas { context, _ in
                        housing.draw(spec, in: &context)
                        let face = housing.face
                        var dome = Path()
                        dome.move(to: CGPoint(x: face.minX + face.width * 0.08, y: face.minY + face.height * 0.12))
                        dome.addLine(to: CGPoint(x: face.minX + face.width * 0.3, y: face.minY + face.height * 0.12))
                        drawGlass(spec, clip: housing.facePath, top: face.minY, middle: face.midY, in: &context, dome: dome, size: side)
                    }
                    GaugeValue(reading: reading, finish: finish, size: min(housing.face.width * 0.3, housing.face.height * 0.5), growsInGrid: true)
                        .frame(width: housing.face.width * 0.9)
                }
                .frame(width: size.width, height: size.height)
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
    }
}

// MARK: - Vertical bar

/// A rectangular instrument in the slot's look: bezel, recessed face, a vertical track that reveals the fixed gradient
/// up to the value (race dash: LED blocks, each in the gradient's color at its place; unlit ones dark),
/// ticks with min and max beside it, the value below.
struct BarGauge: View {
    let reading: GaugeReading
    let finish: GaugeFinish

    var body: some View {
        GaugeCell(reading: reading) {
            AnimatedCanvas(at: reading.range.fraction(reading.number ?? reading.range.min)) { context, size, at in
                draw(&context, size, at: at)
            }
            .animation(GaugeLook.motion(for: reading.sensor), value: reading.number)
            .overlay {
                GeometryReader { geo in
                    let face = Self.housing(geo.size, finish.spec).face
                    GaugeValue(reading: reading, finish: finish, size: face.width * 0.25)
                        .frame(width: face.width * 0.9)
                        .position(x: face.midX, y: face.maxY - face.height * 0.13)
                }
            }
            .aspectRatio(Self.aspect, contentMode: .fit)
        }
    }

    /// Aspect ratio (width / height) of the instrument.
    static let aspect: CGFloat = 0.62

    private static func housing(_ size: CGSize, _ spec: FinishSpec) -> RectHousing {
        RectHousing(CGRect(origin: .zero, size: size), side: min(size.width, size.height), spec)
    }

    private func draw(_ ctx: inout GraphicsContext, _ size: CGSize, at: Double) {
        let spec = finish.spec, range = reading.range
        let housing = Self.housing(size, spec)
        housing.draw(spec, in: &ctx)
        let face = housing.face, facePath = housing.facePath
        let side = housing.side

        // Track: 18 % of the face wide, from near the top to above the value.
        let trackWidth = face.width * 0.18
        let track = CGRect(x: face.midX - trackWidth / 2, y: face.minY + face.height * 0.08,
                           width: trackWidth, height: face.height * 0.66)
        func y(_ fraction: Double) -> CGFloat { track.maxY - track.height * fraction }
        let shows = reading.number != nil
        if finish == .race {
            let count = 16, gap = track.height * 0.012
            for index in 0..<count {
                let from = Double(index) / Double(count), to = Double(index + 1) / Double(count), middle = (from + to) / 2
                ctx.fill(Path(CGRect(x: track.minX, y: y(to) + gap / 2, width: track.width, height: y(from) - y(to) - gap)),
                         with: .color(shows && middle <= at ? range.color(atFraction: middle) : GaugeLook.unlit))
            }
        } else {
            ctx.fill(Path(track), with: .color(GaugeLook.unlit))
            if shows {
                ctx.fill(Path(CGRect(x: track.minX, y: y(at), width: track.width, height: track.maxY - y(at))),
                         with: .linearGradient(range.gradient(), startPoint: CGPoint(x: track.midX, y: track.maxY),
                                               endPoint: CGPoint(x: track.midX, y: track.minY)))
            }
        }

        // Ticks right of the track; numbers only at both ends.
        let gap = face.width * 0.045
        let display = range.converted(for: reading.sensor, reading.units)
        let scale = DialScale(min: display.min, max: display.max)
        let span = display.max - display.min
        if span > 0 {
            for tick in scale.ticks {
                let ty = y((tick.value - display.min) / span)
                var path = Path()
                path.move(to: CGPoint(x: track.maxX + gap, y: ty))
                path.addLine(to: CGPoint(x: track.maxX + gap + face.width * (tick.isMajor ? 0.09 : 0.05), y: ty))
                ctx.stroke(path, with: .color(spec.ink.opacity(tick.isMajor ? 1 : 0.6)), lineWidth: side * (tick.isMajor ? 0.014 : 0.007))
            }
        }
        // Starting past the major ticks; a long one ("7000") shrinks so it stays inside the face.
        let labelX = track.maxX + gap + face.width * 0.12
        let room = face.maxX - labelX - face.width * 0.05
        let ends = [(0.0, display.min), (1.0, display.max)]
        var fontSize = face.width * 0.12
        let widest = ends.map { ctx.resolve(endLabel($0.1).font(finish.font(fontSize))).measure(in: size).width }.max() ?? 0
        if widest > room { fontSize *= room / widest }
        for (fraction, label) in ends {
            ctx.draw(endLabel(label).font(finish.font(fontSize)).foregroundStyle(spec.ink.opacity(0.7)),
                     at: CGPoint(x: labelX, y: y(fraction)), anchor: .leading)
        }

        var dome = Path()
        dome.move(to: CGPoint(x: face.minX + face.width * 0.15, y: face.minY + face.height * 0.06))
        dome.addLine(to: CGPoint(x: face.minX + face.width * 0.15, y: face.minY + face.height * 0.3))
        drawGlass(spec, clip: facePath, top: face.minY, middle: face.midY, in: &ctx, dome: dome, size: side)
    }
}

// MARK: - Arc

/// A round pod in the slot's look: the scale is a thick arc that reveals the fixed gradient up to the value
/// (race dash: LED blocks, each in the gradient's color at its place; unlit ones dark), min and max under its ends,
/// the value in the center.
struct ArcGauge: View {
    let reading: GaugeReading
    let finish: GaugeFinish

    var body: some View {
        GaugeCell(reading: reading) {
            AnimatedCanvas(at: reading.range.fraction(reading.number ?? reading.range.min)) { context, size, at in
                draw(&context, size, at: at)
            }
            .animation(GaugeLook.motion(for: reading.sensor), value: reading.number)
            .overlay {
                GeometryReader { geo in
                    let f = Dial(geo.size).r * (1 - finish.spec.bezel)
                    GaugeValue(reading: reading, finish: finish, size: f * 0.4)
                        .frame(width: f * 1.1)
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                }
            }
            .aspectRatio(1, contentMode: .fit)
        }
    }

    private func draw(_ ctx: inout GraphicsContext, _ size: CGSize, at: Double) {
        let spec = finish.spec, range = reading.range
        let d = Dial(size)
        let f = drawRoundHousing(spec, d, in: &ctx)
        let track = f * 0.13, trackRadius = f * 0.68
        let shows = reading.number != nil

        if finish == .race {
            let count = 26, gap = 0.012
            for index in 0..<count {
                let from = Double(index) / Double(count), to = Double(index + 1) / Double(count), middle = (from + to) / 2
                ctx.stroke(d.arc(from + gap / 2, to - gap / 2, radius: trackRadius),
                           with: .color(shows && middle <= at ? range.color(atFraction: middle) : GaugeLook.unlit), lineWidth: track)
            }
        } else {
            ctx.stroke(d.arc(0, 1, radius: trackRadius), with: .color(GaugeLook.unlit), lineWidth: track)
            if shows, at > 0 {
                // The gradient turns with the scale: 260° of a 360° conic gradient, starting where the scale starts.
                ctx.stroke(d.arc(0, at, radius: trackRadius),
                           with: .conicGradient(range.gradient(length: GaugeLook.arcSweep / 360), center: d.center,
                                                angle: .degrees(GaugeLook.arcStart)),
                           lineWidth: track)
            }
        }

        let display = range.converted(for: reading.sensor, reading.units)
        for (end, label) in [(0.0, display.min), (1.0, display.max)] {
            let p = d.point(end, trackRadius)
            ctx.draw(endLabel(label).font(finish.font(f * 0.12)).foregroundStyle(spec.ink.opacity(0.7)),
                     at: CGPoint(x: p.x, y: p.y + f * 0.17))
        }

        drawRoundGlass(spec, d, face: f, in: &ctx)
    }
}

// MARK: - Gauges page

/// One gauge drawn in the slot's style and look.
struct StyledGauge: View {
    let style: GaugeStyle
    let finish: GaugeFinish
    let reading: GaugeReading

    var body: some View {
        switch style {
        case .analog: AnalogGauge(reading: reading, finish: finish)
        case .digital: DigitalGauge(reading: reading, finish: finish)
        case .bar: BarGauge(reading: reading, finish: finish)
        case .arc: ArcGauge(reading: reading, finish: finish)
        }
    }
}

/// The gauges page grid (`GaugeLayout.grid`), shared by Live gauges and the gauge editor so both place the gauges the same way.
/// `cell` draws the gauge at an index from 0 to `count` − 1; an empty cell stays blank.
/// Every value text in the grid gets one size (`GaugeLook.valueSize`), so no style looks huge next to another.
struct GaugeGrid<Cell: View>: View {
    let count: Int
    @ViewBuilder let cell: (Int) -> Cell

    var body: some View {
        GeometryReader { geo in
            let grid = GaugeLayout.grid(for: count, wide: geo.size.width > geo.size.height)
            let cellSize = CGSize(width: geo.size.width / CGFloat(grid.columns) - 2 * GaugeLook.gap,
                                  height: geo.size.height / CGFloat(grid.rows) - 2 * GaugeLook.gap)
            VStack(spacing: 0) {
                ForEach(0..<grid.rows, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<grid.columns, id: \.self) { column in
                            let index = row * grid.columns + column
                            Group {
                                if index < count { cell(index).padding(GaugeLook.gap) } else { Color.clear }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                }
            }
            .environment(\.gaugeValueSize, GaugeLook.valueSize(cell: cellSize))
        }
    }
}

/// Landscape (iPhone): the navigation bar is hidden so the gauges get the whole screen.
/// Any tap shows it again for 3 s, the way back. Portrait: always shown.
private struct LandscapeFullScreen: ViewModifier {
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var taps = 0
    @State private var showsBar = false

    func body(content: Content) -> some View {
        content
            .contentShape(.rect)
            // Simultaneous, so a tap on a gauge in the editor still opens its sheet.
            .simultaneousGesture(TapGesture().onEnded { taps += 1 })
            .toolbar(verticalSizeClass == .compact && !showsBar ? .hidden : .visible, for: .navigationBar)
            .task(id: taps) {
                guard taps > 0 else { return }
                showsBar = true
                // A new tap cancels this wait and starts the 3 s again.
                try? await Task.sleep(for: .seconds(3))
                if !Task.isCancelled { showsBar = false }
            }
    }
}

extension View {
    func landscapeFullScreen() -> some View { modifier(LandscapeFullScreen()) }
}
