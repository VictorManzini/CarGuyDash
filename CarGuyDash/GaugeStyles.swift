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

/// The dial arc of the analog and arc styles: 260°, open at the bottom, starting lower left.
private let arcStart = 140.0
private let arcSweep = 260.0

/// The empty part of the bar and arc: very dark grey, opaque.
private let trackColor = Color(red: 0x1C / 255, green: 0x1C / 255, blue: 0x1E / 255)
private let fillAnimation = Animation.easeOut(duration: 0.25)

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

// MARK: - Analog

/// Old racing tachometer: dark face, numbers around the arc, orange band up to the redline,
/// red band from it, red needle.
struct AnalogGauge: View {
    let reading: GaugeReading

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Canvas { context, size in drawDial(in: &context, size: size) }
                // Needle and hub hidden without a number: they would cross the "Stand By" / "N/A" text.
                Group {
                    Needle()
                        .fill(GaugeColor.red.color)
                        .shadow(color: GaugeColor.red.color.opacity(0.6), radius: 3)
                        .rotationEffect(.degrees(arcStart + arcSweep * reading.range.fraction(reading.number ?? reading.range.min)))
                        .animation(fillAnimation, value: reading.number)
                    Circle().fill(.black).frame(width: 14).overlay(Circle().stroke(Color(white: 0.35), lineWidth: 1))
                }
                .opacity(reading.number == nil ? 0 : 1)
                if reading.number == nil {
                    // Stand By / N/A: near-transparent grey layer + red text in the center.
                    Circle().fill(.gray.opacity(0.35))
                    Text(reading.text).font(.headline).foregroundStyle(GaugeColor.red.color)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            GaugeName(name: reading.name ?? reading.sensor.name)
        }
    }

    private func drawDial(in context: inout GraphicsContext, size: CGSize) {
        let r = min(size.width, size.height) / 2
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        func point(_ fraction: Double, _ radius: CGFloat) -> CGPoint {
            let angle = Angle.degrees(arcStart + arcSweep * fraction).radians
            return CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
        }

        // Face and bezel.
        func circle(_ radius: CGFloat) -> Path {
            Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius))
        }
        context.fill(circle(r), with: .radialGradient(Gradient(colors: [Color(white: 0.1), Color(white: 0.02)]),
                                                      center: center, startRadius: 0, endRadius: r))
        // Thin metallic rim: mid grey at the top left fading to dark grey at the bottom right.
        context.stroke(circle(r * 0.985), with: .linearGradient(
            Gradient(colors: [Color(white: 0.55), Color(white: 0.2)]),
            startPoint: CGPoint(x: center.x - r, y: center.y - r), endPoint: CGPoint(x: center.x + r, y: center.y + r)),
                       lineWidth: r * 0.03)

        // Bands on the outer edge: orange from normalHigh to the redline, red from the redline to max.
        // None when they have no width (other sensors: normalHigh = redline = max).
        let display = reading.range.converted(for: reading.sensor, reading.units)
        let orangeFrom = reading.range.fraction(reading.range.normalHigh)
        let redFrom = reading.range.fraction(reading.range.redline)
        for (from, to, color) in [(orangeFrom, redFrom, GaugeColor.orange), (redFrom, 1, .red)] where from < to {
            var band = Path()
            band.addArc(center: center, radius: r * 0.905, startAngle: .degrees(arcStart + arcSweep * from),
                        endAngle: .degrees(arcStart + arcSweep * to), clockwise: false)
            context.stroke(band, with: .color(color.color), lineWidth: r * 0.045)
        }

        // Ticks and numbers, in the chosen units. Big scales (RPM) are labelled in thousands.
        let span = display.max - display.min
        guard span > 0 else { return }
        let step = Self.labelStep(for: span)
        let scale = step >= 1000 ? 1000.0 : 1
        let minor = step / 4
        var value = (display.min / minor).rounded(.up) * minor
        while value <= display.max + minor / 1000 {
            let fraction = (value - display.min) / span
            let isMajor = abs((value / step).rounded() * step - value) < minor / 1000
            let color = fraction >= redFrom - 0.0001 && redFrom < 1 ? GaugeColor.red.color : Color(white: 0.88)
            var tick = Path()
            tick.move(to: point(fraction, r * 0.86))
            tick.addLine(to: point(fraction, r * (isMajor ? 0.73 : 0.8)))
            context.stroke(tick, with: .color(color.opacity(isMajor ? 1 : 0.6)), lineWidth: isMajor ? r * 0.018 : r * 0.008)
            if isMajor {
                let label = Text(String(format: "%g", value / scale))
                    .font(.system(size: r * 0.14, weight: .semibold).monospacedDigit())
                    .foregroundStyle(color)
                context.draw(label, at: point(fraction, r * 0.58))
            }
            value += minor
        }

        let unit = reading.sensor.displayUnit(reading.units)
        context.draw(Text(scale == 1000 ? "×1000 \(unit)" : unit)
                        .font(.system(size: r * 0.09, weight: .medium))
                        .foregroundStyle(Color(white: 0.55)),
                     at: CGPoint(x: center.x, y: center.y + r * 0.42))
    }

    /// Distance between numbers on the dial, for 4 to 8 of them: 1, 2, 2.5 or 5 times a power of ten.
    static func labelStep(for span: Double) -> Double {
        let raw = span / 8
        let power = pow(10, floor(log10(raw)))
        return [1, 2, 2.5, 5, 10].map { $0 * power }.first { $0 >= raw } ?? raw
    }
}

/// Points right (0°) from the center, with a short tail; rotated to the value.
private struct Needle: Shape {
    func path(in rect: CGRect) -> Path {
        let r = min(rect.width, rect.height) / 2
        let c = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()
        path.move(to: CGPoint(x: c.x - r * 0.15, y: c.y - r * 0.025))
        path.addLine(to: CGPoint(x: c.x + r * 0.86, y: c.y - r * 0.008))
        path.addLine(to: CGPoint(x: c.x + r * 0.86, y: c.y + r * 0.008))
        path.addLine(to: CGPoint(x: c.x - r * 0.15, y: c.y + r * 0.025))
        path.closeSubpath()
        return path
    }
}

// MARK: - Digital

/// Big number: white, red only from the redline.
struct DigitalGauge: View {
    let reading: GaugeReading

    var body: some View {
        VStack(spacing: 8) {
            GaugeValue(reading: reading, size: 64).frame(maxHeight: .infinity)
            GaugeName(name: reading.name ?? reading.sensor.name)
        }
    }
}

// MARK: - Vertical bar

/// The gradient is fixed on the scale; the fill only reveals it up to the current value.
struct BarGauge: View {
    let reading: GaugeReading

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                let height = geo.size.height * (reading.number.map(reading.range.fraction) ?? 0)
                ZStack(alignment: .bottom) {
                    trackColor
                    LinearGradient(stops: reading.range.gradientStops, startPoint: .bottom, endPoint: .top)
                        .mask(alignment: .bottom) { Rectangle().frame(height: height) }
                    if reading.number != nil {
                        // Soft glow in the gradient's own color at the top of the fill.
                        Rectangle()
                            .fill(reading.tipColor)
                            .frame(height: 2)
                            .shadow(color: reading.tipColor, radius: 4)
                            .offset(y: -max(height - 2, 0))
                    }
                }
                .animation(fillAnimation, value: reading.number)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .frame(width: 36)
            .frame(maxHeight: .infinity)
            GaugeValue(reading: reading, size: 28)
            GaugeName(name: reading.name ?? reading.sensor.name)
        }
    }
}

// MARK: - Arc

/// Same colors as the bar, on an arc open at the bottom; the value in the center.
struct ArcGauge: View {
    let reading: GaugeReading
    private let width: CGFloat = 14

    var body: some View {
        ZStack {
            let fraction = reading.number.map(reading.range.fraction) ?? 0
            arc(0, 1).stroke(trackColor, lineWidth: width)
            arc(0, fraction)
                .stroke(AngularGradient(stops: reading.range.gradientStops, center: .center,
                                        startAngle: .degrees(arcStart), endAngle: .degrees(arcStart + arcSweep)),
                        lineWidth: width)
                .animation(fillAnimation, value: reading.number)
            if reading.number != nil {
                // Soft glow in the gradient's own color on the last bit of the fill.
                arc(max(fraction - 0.012, 0), fraction)
                    .stroke(reading.tipColor, lineWidth: width)
                    .shadow(color: reading.tipColor, radius: 5)
                    .animation(fillAnimation, value: reading.number)
            }
            GaugeValue(reading: reading, size: 34).padding(.horizontal, width * 2)
        }
        .aspectRatio(1, contentMode: .fit)
        // The name sits in the opening at the bottom, below the arc's ends.
        .overlay(alignment: .bottom) { GaugeName(name: reading.name ?? reading.sensor.name) }
    }

    private func arc(_ from: Double, _ to: Double) -> some Shape {
        Circle().inset(by: width / 2).trim(from: arcSweep / 360 * from, to: arcSweep / 360 * to).rotation(.degrees(arcStart))
    }
}

// MARK: - Shared parts

/// Number + small unit: white, red from the redline. "Stand By" / "N/A" replace the number, in grey.
private struct GaugeValue: View {
    let reading: GaugeReading
    let size: CGFloat

    var body: some View {
        Group {
            if reading.number == nil {
                Text(reading.text)
                    .font(.system(size: size * 0.55, weight: .semibold))
                    .foregroundStyle(.secondary)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(reading.text)
                        .font(.system(size: size, weight: .semibold).monospacedDigit())
                        .foregroundStyle(reading.isRedline ? GaugeColor.red.color : .white)
                    Text(reading.sensor.displayUnit(reading.units))
                        .font(.system(size: size * 0.32, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.4)
    }
}

/// Sensor name below the gauge, outside it: small capitals, spaced out, light grey.
private struct GaugeName: View {
    let name: String

    var body: some View {
        Text(name.uppercased())
            .font(.system(size: 11, weight: .medium))
            .tracking(1.2)
            .foregroundStyle(Color(white: 0.7))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}
