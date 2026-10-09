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

    /// The value to draw; nil while the text is "Stand By" or "N/A" (no needle movement, no fill).
    var number: Double? { text == "Stand By" || text == "N/A" ? nil : value }
    var isRedline: Bool { number.map { $0 >= range.redline } ?? false }
}

/// The dial arc of the analog and arc styles: 260°, open at the bottom, starting lower left.
private let arcStart = 140.0
private let arcSweep = 260.0

extension GaugeColor {
    var color: Color {
        switch self {
        case .blue: .blue
        case .green: .green
        case .yellow: .yellow
        case .red: .red
        }
    }
}

extension GaugeRange {
    var gradientStops: [Gradient.Stop] { stops.map { Gradient.Stop(color: $0.color.color, location: $0.at) } }
}

// MARK: - Analog

/// Old racing tachometer: dark face, numbers around the arc, red redline band, red needle.
struct AnalogGauge: View {
    let reading: GaugeReading

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Canvas { context, size in drawDial(in: &context, size: size) }
                Needle()
                    .fill(.red)
                    .rotationEffect(.degrees(arcStart + arcSweep * reading.range.fraction(reading.number ?? reading.range.min)))
                    .animation(.easeOut(duration: 0.25), value: reading.number)
                    .shadow(color: .black.opacity(0.6), radius: 2, y: 1)
                    // Hidden without a number: red on red would hide the "Stand By" / "N/A" text.
                    .opacity(reading.number == nil ? 0 : 1)
                Circle().fill(Color(white: 0.15)).frame(width: 14).overlay(Circle().stroke(Color(white: 0.35), lineWidth: 1))
                if reading.number == nil {
                    // Stand By / N/A: near-transparent grey layer + red text in the center.
                    Circle().fill(.gray.opacity(0.35))
                    Text(reading.text).font(.headline).foregroundStyle(.red)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            GaugeName(sensor: reading.sensor)
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
        context.fill(circle(r), with: .radialGradient(Gradient(colors: [Color(white: 0.16), Color(white: 0.04)]),
                                                      center: center, startRadius: 0, endRadius: r))
        context.stroke(circle(r * 0.975), with: .linearGradient(
            Gradient(colors: [Color(white: 0.55), Color(white: 0.2)]),
            startPoint: CGPoint(x: center.x, y: center.y - r), endPoint: CGPoint(x: center.x, y: center.y + r)), lineWidth: r * 0.05)

        // Redline band: from the redline to the end of the scale (none when redline = max).
        let display = reading.range.converted(for: reading.sensor, reading.units)
        let redFrom = reading.range.fraction(reading.range.redline)
        if redFrom < 1 {
            var band = Path()
            band.addArc(center: center, radius: r * 0.905, startAngle: .degrees(arcStart + arcSweep * redFrom),
                        endAngle: .degrees(arcStart + arcSweep), clockwise: false)
            context.stroke(band, with: .color(.red), lineWidth: r * 0.05)
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
            let color: Color = fraction >= redFrom - 0.0001 && redFrom < 1 ? .red : .white
            var tick = Path()
            tick.move(to: point(fraction, r * 0.86))
            tick.addLine(to: point(fraction, r * (isMajor ? 0.72 : 0.79)))
            context.stroke(tick, with: .color(color.opacity(isMajor ? 1 : 0.7)), lineWidth: isMajor ? r * 0.025 : r * 0.012)
            if isMajor {
                let label = Text(String(format: "%g", value / scale))
                    .font(.system(size: r * 0.15, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
                context.draw(label, at: point(fraction, r * 0.56))
            }
            value += minor
        }

        let unit = reading.sensor.displayUnit(reading.units)
        context.draw(Text(scale == 1000 ? "×1000 \(unit)" : unit)
                        .font(.system(size: r * 0.1, weight: .medium))
                        .foregroundStyle(Color(white: 0.6)),
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
            GaugeName(sensor: reading.sensor)
        }
    }
}

// MARK: - Vertical bar

/// The gradient is fixed on the scale; the fill only reveals it up to the current value.
struct BarGauge: View {
    let reading: GaugeReading

    var body: some View {
        VStack(spacing: 8) {
            let bar = RoundedRectangle(cornerRadius: 8)
            ZStack {
                bar.fill(Color.white.opacity(0.1))
                LinearGradient(stops: reading.range.gradientStops, startPoint: .bottom, endPoint: .top)
                    .mask {
                        Rectangle().scaleEffect(x: 1, y: reading.number.map(reading.range.fraction) ?? 0, anchor: .bottom)
                    }
                    .clipShape(bar)
                    .animation(.easeOut(duration: 0.25), value: reading.number)
            }
            .frame(width: 36)
            .frame(maxHeight: .infinity)
            GaugeValue(reading: reading, size: 28)
            GaugeName(sensor: reading.sensor)
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
            arc(to: 1).stroke(Color.white.opacity(0.1), lineWidth: width)
            arc(to: reading.number.map(reading.range.fraction) ?? 0)
                .stroke(AngularGradient(stops: reading.range.gradientStops, center: .center,
                                        startAngle: .degrees(arcStart), endAngle: .degrees(arcStart + arcSweep)),
                        lineWidth: width)
                .animation(.easeOut(duration: 0.25), value: reading.number)
            GaugeValue(reading: reading, size: 34).padding(.horizontal, width * 2)
        }
        .aspectRatio(1, contentMode: .fit)
        // The name sits in the opening at the bottom, below the arc's ends.
        .overlay(alignment: .bottom) { GaugeName(sensor: reading.sensor) }
    }

    private func arc(to fraction: Double) -> some Shape {
        Circle().inset(by: width / 2).trim(from: 0, to: arcSweep / 360 * fraction).rotation(.degrees(arcStart))
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
                    .font(.system(size: size * 0.55, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(reading.text)
                        .font(.system(size: size, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(reading.isRedline ? .red : .white)
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

/// Sensor name below the gauge, outside it.
private struct GaugeName: View {
    let sensor: Sensor

    var body: some View {
        Text(sensor.name)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}
