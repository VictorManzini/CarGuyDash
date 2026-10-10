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
    var isRedline: Bool { number.map { $0 >= range.redline } ?? false }
}

// MARK: - Shared look

/// The one set of measures, colors and type every style uses, so the four look like one family.
enum GaugeLook {
    /// Spacing scale: 4 / 8 / 16.
    static let gapSmall: CGFloat = 4
    static let gap: CGFloat = 8
    static let gapLarge: CGFloat = 16
    /// Thickness of the bar and of the arc, the same in both.
    static let track: CGFloat = 14
    /// The empty part of the bar and arc: very dark grey, opaque.
    static let trackColor = Color(red: 0x1C / 255, green: 0x1C / 255, blue: 0x1E / 255)

    /// Numbers and dial labels. Secondary: units, names, Stand By / N/A (about 7:1 on black).
    static let primary = Color(white: 0.94)
    static let secondary = Color(white: 0.62)

    /// The dial arc of the analog and arc styles: 260°, open at the bottom, starting lower left.
    static let arcStart = 140.0
    static let arcSweep = 260.0
    /// How much of the square the arc style uses: down to the arc's ends (sin 40°).
    static let arcHeight = 0.5 + 0.5 * sin(40 * Double.pi / 180)

    /// Critically damped: follows the value smoothly, never overshoots.
    static let motion = Animation.spring(response: 0.3, dampingFraction: 1)

    /// Same family everywhere: SF Pro, semibold numbers with fixed-width digits, medium units.
    static func number(_ size: CGFloat) -> Font { .system(size: size, weight: .semibold).monospacedDigit() }
    static func unit(_ size: CGFloat) -> Font { .system(size: size * 0.36, weight: .medium) }
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
    var gradientStops: [Gradient.Stop] { stops.map { Gradient.Stop(color: $0.color.color, location: $0.at) } }
}

extension GaugeReading {
    /// The gradient's color where the fill ends, for the glow at its tip.
    var tipColor: Color { Color(rgb: range.rgb(at: number ?? range.min)) }
}

/// Every style: the gauge sits on the bottom of its space, the name always `GaugeLook.gap` below it,
/// so names in one row line up whatever the styles.
private struct GaugeCell<Content: View>: View {
    let reading: GaugeReading
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: GaugeLook.gap) {
            content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            Text((reading.name ?? reading.sensor.name).uppercased())
                .font(.system(size: 11, weight: .medium))
                .tracking(1.2) // small text: a little looser
                .foregroundStyle(GaugeLook.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

/// Number and unit as one text, so they share one baseline and shrink together.
/// Red from the redline. "Stand By" / "N/A" replace both, in grey.
private struct GaugeValue: View {
    let reading: GaugeReading
    let size: CGFloat

    var body: some View {
        Group {
            if reading.number == nil {
                Text(reading.text).font(.system(size: size * 0.5, weight: .semibold)).foregroundStyle(GaugeLook.secondary)
            } else {
                let unit = reading.sensor.displayUnit(reading.units)
                let number = Text(reading.text)
                    .font(GaugeLook.number(size))
                    .tracking(-size * 0.02) // big digits: a little tighter
                    .foregroundStyle(reading.isRedline ? GaugeColor.red.color : GaugeLook.primary)
                // Thin space between number and unit.
                let suffix = Text(unit.isEmpty ? "" : "\u{2009}" + unit).font(GaugeLook.unit(size)).foregroundStyle(GaugeLook.secondary)
                Text("\(number)\(suffix)")
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.4)
    }
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

/// Old racing tachometer: metallic rim, dark face with an inner shadow, numbers on an outer ring,
/// ticks and the orange / red bands inside them, red needle that stops at the ticks (never over a number).
struct AnalogGauge: View {
    let reading: GaugeReading

    /// Radii, as a fraction of the dial's radius.
    private enum R {
        static let face = 0.955
        static let labelInner = 0.74
        static let band = 0.7
        static let tickOuter = 0.68
        static let majorInner = 0.56
        static let minorInner = 0.62
        static let needle = 0.66
    }

    var body: some View {
        GaugeCell(reading: reading) {
            ZStack {
                Canvas { context, size in drawDial(in: &context, size: size) }
                Group {
                    Needle(length: R.needle)
                        .fill(GaugeColor.red.color)
                        .shadow(color: GaugeColor.red.color.opacity(0.5), radius: 3)
                        .rotationEffect(.degrees(GaugeLook.arcStart + GaugeLook.arcSweep * reading.range.fraction(reading.number ?? reading.range.min)))
                        .animation(GaugeLook.motion, value: reading.number)
                    Hub().fill(.black).overlay(Hub().stroke(Color(white: 0.35), lineWidth: 1))
                }
                // Needle and hub hidden without a number: they would cross the "Stand By" / "N/A" text.
                .opacity(reading.number == nil ? 0 : 1)
                if reading.number == nil {
                    // Stand By / N/A: near-transparent grey layer + red text in the center.
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

    private func drawDial(in context: inout GraphicsContext, size: CGSize) {
        let r = min(size.width, size.height) / 2
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        func circle(_ radius: CGFloat) -> Path {
            Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius))
        }
        func angle(_ fraction: Double) -> Double { Angle.degrees(GaugeLook.arcStart + GaugeLook.arcSweep * fraction).radians }
        func point(_ fraction: Double, _ radius: CGFloat) -> CGPoint {
            CGPoint(x: center.x + radius * cos(angle(fraction)), y: center.y + radius * sin(angle(fraction)))
        }

        // Face: lighter in the middle, then an inner shadow along the rim so it sits below it.
        context.fill(circle(r * R.face), with: .radialGradient(Gradient(colors: [Color(white: 0.11), Color(white: 0.03)]),
                                                               center: center, startRadius: 0, endRadius: r * R.face))
        context.drawLayer { layer in
            layer.clip(to: circle(r * R.face))
            layer.addFilter(.blur(radius: r * 0.05))
            layer.stroke(circle(r * R.face), with: .color(.black.opacity(0.9)), lineWidth: r * 0.12)
        }

        // Rim: brushed metal (light and dark streaks around it), lit from the top, thin dark seam inside.
        let rimRadius = r * (1 + R.face) / 2, rimWidth = r * (1 - R.face)
        context.stroke(circle(rimRadius), with: .conicGradient(
            Gradient(colors: [0.78, 0.36, 0.62, 0.28, 0.7, 0.32, 0.58, 0.3, 0.78].map { Color(white: $0) }),
            center: center, angle: .degrees(-45)), lineWidth: rimWidth)
        context.stroke(circle(rimRadius), with: .linearGradient(
            Gradient(colors: [.white.opacity(0.25), .clear, .black.opacity(0.35)]),
            startPoint: CGPoint(x: center.x, y: center.y - r), endPoint: CGPoint(x: center.x, y: center.y + r)), lineWidth: rimWidth)
        context.stroke(circle(r * R.face), with: .color(.black), lineWidth: max(1, r * 0.008))

        // Bands just outside the ticks: orange from normalHigh to the redline, red from the redline to max.
        // None when they have no width (normalHigh = redline = max).
        let orangeFrom = reading.range.fraction(reading.range.normalHigh)
        let redFrom = reading.range.fraction(reading.range.redline)
        for (from, to, color) in [(orangeFrom, redFrom, GaugeColor.orange), (redFrom, 1, .red)] where from < to {
            var band = Path()
            band.addArc(center: center, radius: r * R.band, startAngle: .radians(angle(from)), endAngle: .radians(angle(to)), clockwise: false)
            context.stroke(band, with: .color(color.color), lineWidth: r * 0.035)
        }

        // Ticks and numbers in the chosen units.
        let display = reading.range.converted(for: reading.sensor, reading.units)
        let scale = DialScale(min: display.min, max: display.max)
        let span = display.max - display.min
        guard span > 0 else { return }
        func isRed(_ fraction: Double) -> Bool { redFrom < 1 && fraction >= redFrom - 0.0001 }
        for tick in scale.ticks {
            let fraction = (tick.value - display.min) / span
            var path = Path()
            path.move(to: point(fraction, r * R.tickOuter))
            path.addLine(to: point(fraction, r * (tick.isMajor ? R.majorInner : R.minorInner)))
            let color = isRed(fraction) ? GaugeColor.red.color : GaugeLook.primary
            context.stroke(path, with: .color(color.opacity(tick.isMajor ? 1 : 0.55)), lineWidth: r * (tick.isMajor ? 0.022 : 0.01))
        }

        // Numbers: each measured and pushed out to start on the same circle just outside the ticks, centered on
        // its major tick's angle, so a wide one ("-0.5", "200") keeps the same distance from the ticks as a narrow one.
        let majors = scale.ticks.filter(\.isMajor)
        // One size on every dial; only labels too long for the ring (kPa: "-100") shrink, so they stay off the rim.
        var fontSize = r * 0.11
        let widest = majors.map { context.resolve(Text(scale.label($0.value)).font(GaugeLook.number(fontSize))).measure(in: size).width }.max() ?? 0
        if widest > r * 0.19 { fontSize *= r * 0.19 / widest }
        for tick in majors {
            let fraction = (tick.value - display.min) / span
            let label = context.resolve(Text(scale.label(tick.value))
                .font(GaugeLook.number(fontSize))
                .foregroundStyle(isRed(fraction) ? GaugeColor.red.color : GaugeLook.primary))
            let box = label.measure(in: size)
            // Half the box's reach along the radius; the digits' visible height is about 0.72 of the line.
            let reach = (box.width * abs(cos(angle(fraction))) + box.height * 0.72 * abs(sin(angle(fraction)))) / 2
            context.draw(label, at: point(fraction, r * R.labelInner + reach))
        }

        let unit = reading.sensor.displayUnit(reading.units)
        context.draw(Text(scale.divisor == 1000 ? "×1000 \(unit)" : unit)
                        .font(.system(size: r * 0.085, weight: .medium))
                        .foregroundStyle(GaugeLook.secondary),
                     at: CGPoint(x: center.x, y: center.y + r * 0.34))
    }
}

/// Points right (0°) from the center up to `length` × radius, with a short tail; rotated to the value.
private struct Needle: Shape {
    let length: Double

    func path(in rect: CGRect) -> Path {
        let r = min(rect.width, rect.height) / 2
        let c = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()
        path.move(to: CGPoint(x: c.x - r * 0.14, y: c.y - r * 0.024))
        path.addLine(to: CGPoint(x: c.x + r * length, y: c.y - r * 0.007))
        path.addLine(to: CGPoint(x: c.x + r * length, y: c.y + r * 0.007))
        path.addLine(to: CGPoint(x: c.x - r * 0.14, y: c.y + r * 0.024))
        path.closeSubpath()
        return path
    }
}

/// The black cap over the needle's pivot, sized with the dial.
private struct Hub: Shape {
    func path(in rect: CGRect) -> Path {
        let radius = min(rect.width, rect.height) * 0.04
        return Path(ellipseIn: CGRect(x: rect.midX - radius, y: rect.midY - radius, width: 2 * radius, height: 2 * radius))
    }
}

// MARK: - Digital

/// Big number: white, red only from the redline. Its size follows the space it has.
/// The number (or Stand By / N/A) is centered in the space above the name; the name stays on the row's shared line.
struct DigitalGauge: View {
    let reading: GaugeReading

    var body: some View {
        GaugeCell(reading: reading) {
            GeometryReader { geo in
                GaugeValue(reading: reading, size: min(geo.size.width * 0.34, geo.size.height * 0.6))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

// MARK: - Vertical bar

/// The gradient is fixed on the scale; the fill only reveals it up to the current value.
struct BarGauge: View {
    let reading: GaugeReading

    var body: some View {
        GaugeCell(reading: reading) {
            GeometryReader { cell in
            VStack(spacing: GaugeLook.gap) {
                GeometryReader { geo in
                    let height = geo.size.height * (reading.number.map(reading.range.fraction) ?? 0)
                    ZStack(alignment: .bottom) {
                        ZStack(alignment: .bottom) {
                            GaugeLook.trackColor
                            LinearGradient(stops: reading.range.gradientStops, startPoint: .bottom, endPoint: .top)
                                .mask(alignment: .bottom) { Rectangle().frame(height: height) }
                        }
                        .clipShape(Capsule())
                        if reading.number != nil {
                            TipGlow(color: reading.tipColor).offset(y: -(height - GaugeLook.track * 0.6))
                        }
                    }
                    .animation(GaugeLook.motion, value: reading.number)
                }
                .frame(width: GaugeLook.track)
                // Same size as the arc's value in a cell of the same width.
                GaugeValue(reading: reading, size: cell.size.width * 0.2)
            }
            .frame(width: cell.size.width, height: cell.size.height)
            }
        }
    }
}

// MARK: - Arc

/// Same colors as the bar, on an arc open at the bottom; the value in the center.
struct ArcGauge: View {
    let reading: GaugeReading

    var body: some View {
        GaugeCell(reading: reading) {
            // Only as tall as the arc's ends, so the name is the same distance below it as below the other styles.
            Color.clear
                .aspectRatio(1 / GaugeLook.arcHeight, contentMode: .fit)
                .overlay(alignment: .top) {
                    GeometryReader { geo in
                        let d = geo.size.width
                        let fraction = reading.number.map(reading.range.fraction) ?? 0
                        ZStack {
                            arc(0, 1).stroke(GaugeLook.trackColor, lineWidth: GaugeLook.track)
                            arc(0, fraction)
                                .stroke(AngularGradient(stops: reading.range.gradientStops, center: .center,
                                                        startAngle: .degrees(GaugeLook.arcStart),
                                                        endAngle: .degrees(GaugeLook.arcStart + GaugeLook.arcSweep)),
                                        lineWidth: GaugeLook.track)
                                .animation(GaugeLook.motion, value: reading.number)
                            if reading.number != nil {
                                // A soft round light on the fill's end, on the arc's center line.
                                TipGlow(color: reading.tipColor)
                                    .offset(x: d / 2 - GaugeLook.track / 2)
                                    .frame(width: d, height: d)
                                    .rotationEffect(.degrees(GaugeLook.arcStart + GaugeLook.arcSweep * fraction))
                                    .animation(GaugeLook.motion, value: reading.number)
                            }
                            GaugeValue(reading: reading, size: d * 0.2).padding(.horizontal, GaugeLook.track * 2)
                        }
                        .frame(width: d, height: d)
                    }
                }
        }
    }

    private func arc(_ from: Double, _ to: Double) -> some Shape {
        Circle()
            .inset(by: GaugeLook.track / 2)
            .trim(from: GaugeLook.arcSweep / 360 * from, to: GaugeLook.arcSweep / 360 * to)
            .rotation(.degrees(GaugeLook.arcStart))
    }
}

/// The subtle glow at the end of a bar or arc fill: a blurred round light in the gradient's own color.
/// Round and soft, so the end of the fill stays clean (no lighter square).
private struct TipGlow: View {
    let color: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: GaugeLook.track * 1.2, height: GaugeLook.track * 1.2)
            .blur(radius: GaugeLook.track * 0.45)
            .opacity(0.6)
            .allowsHitTesting(false)
    }
}

// MARK: - Gauges page

/// One gauge drawn in the slot's style.
struct StyledGauge: View {
    let style: GaugeStyle
    let reading: GaugeReading

    var body: some View {
        switch style {
        case .analog: AnalogGauge(reading: reading)
        case .digital: DigitalGauge(reading: reading)
        case .bar: BarGauge(reading: reading)
        case .arc: ArcGauge(reading: reading)
        }
    }
}

/// The gauges page grid (`GaugeLayout.grid`), shared by Live gauges and the gauge editor so both place the gauges the same way.
/// `cell` draws the gauge at an index from 0 to `count` − 1; an empty cell stays blank.
struct GaugeGrid<Cell: View>: View {
    let count: Int
    @ViewBuilder let cell: (Int) -> Cell

    var body: some View {
        GeometryReader { geo in
            let grid = GaugeLayout.grid(for: count, wide: geo.size.width > geo.size.height)
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
        }
    }
}
