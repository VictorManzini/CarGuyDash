#if DEBUG
import SwiftUI

/// Debug only: three candidate looks for the gauges, side by side, to pick one before the real styles change.
/// Every direction drops what makes the current gauges look drawn: no rainbow fills and no glows; one fill color
/// (red only past the redline) with the zones painted on the scale; DIN numbers with tabular digits; a bezel lit
/// from the top, a slightly recessed face and a faint glass reflection.
/// Screenshots: `-openGaugeLab YES -gaugeLab.rpm 6400`, and `-gaugeLab.solo A` (B, C) for one RPM dial full screen.
struct GaugeLabView: View {
    let scanner: BluetoothScanner
    @AppStorage("gaugeLab.rpm") private var rpm = 3000.0
    /// "A", "B" or "C": only that direction's RPM dial, full screen. Empty = the three rows.
    @AppStorage("gaugeLab.solo") private var solo = ""
    /// The highest RPM seen since the screen opened, for the peak marker of direction C.
    @State private var peak = 0.0
    @State private var unitSettings = UnitSettings()

    private static let coolant = 98.0, oil = 95.0

    var body: some View {
        Group {
            if let look = LabLook.all.first(where: { $0.id == solo }) {
                analog(look).padding(GaugeLook.gapLarge).frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: GaugeLook.gapLarge) {
                        ForEach(LabLook.all, id: \.id) { look in
                            Text(look.title).font(.headline)
                            HStack(alignment: .bottom, spacing: GaugeLook.gap) {
                                labeled("RPM") { analog(look) }
                                labeled("Coolant") {
                                    LabArc(look: look, sensor: .coolantTemp, range: scanner.range(for: .sensor(.coolantTemp)),
                                           value: Self.coolant, units: unitSettings.units)
                                }
                                labeled("Oil") {
                                    LabBar(look: look, sensor: .oilTemp, range: scanner.range(for: .sensor(.oilTemp)),
                                           value: Self.oil, units: unitSettings.units)
                                }
                            }
                        }
                    }
                    .padding()
                }
                .safeAreaInset(edge: .bottom) {
                    VStack(spacing: GaugeLook.gapSmall) {
                        Text("RPM \(Int(rpm))").font(.caption).monospacedDigit()
                        Slider(value: $rpm, in: 0...7000, step: 50)
                    }
                    .padding()
                    .background(.bar)
                }
            }
        }
        .onAppear { peak = rpm }
        .onChange(of: rpm) { peak = max(peak, rpm) }
        .navigationTitle("Gauge lab")
        .navigationBarTitleDisplayMode(.inline)
        .background(.black)
        .preferredColorScheme(.dark)
    }

    private func analog(_ look: LabLook) -> some View {
        LabAnalog(look: look, sensor: .rpm, range: scanner.range(for: .sensor(.rpm)), value: rpm, peak: peak, units: unitSettings.units)
    }

    private func labeled(_ name: String, @ViewBuilder gauge: () -> some View) -> some View {
        VStack(spacing: GaugeLook.gapSmall) {
            gauge().frame(height: 150)
            Text(name.uppercased()).font(.system(size: 10, weight: .medium)).tracking(1).foregroundStyle(GaugeLook.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Directions

/// One candidate look: the materials, the ink and the extras of a direction.
private struct LabLook {
    let id: String
    let title: String
    /// Bezel thickness as a fraction of the radius; its color at the top (lit) and at the bottom.
    let bezel: Double
    let bezelTop: Color
    let bezelBottom: Color
    let faceCenter: Color
    let faceEdge: Color
    /// Ticks and numbers.
    let ink: Color
    /// DIN Condensed instead of DIN Alternate.
    let condensed: Bool
    /// Dial number size, as a fraction of the face radius.
    let numberSize: Double
    /// Width of the zones painted on the scale, as a fraction of the face radius.
    let zoneWidth: Double
    let needle: Color
    /// The fill of the arc and bar below the redline.
    let fill: Color
    /// LED blocks instead of a continuous fill, and the shift lights over the RPM dial.
    let race: Bool
    /// The small red tick at the highest value seen.
    let peakMarker: Bool
    /// The glass reflection's opacity at its brightest; `dome` adds a curved highlight like a domed lens.
    let glass: Double
    let dome: Bool

    func font(_ size: CGFloat) -> Font {
        .custom(condensed ? "DINCondensed-Bold" : "DINAlternate-Bold", size: size).monospacedDigit()
    }

    /// A: factory instrument cluster. Matte black face, thin satin-chrome bezel, thin white ink, orange-red needle.
    static let oem = LabLook(id: "A", title: "A · OEM cluster", bezel: 0.05,
                             bezelTop: Color(white: 0.82), bezelBottom: Color(white: 0.3),
                             faceCenter: Color(white: 0.085), faceEdge: Color(white: 0.045), ink: Color(white: 0.92),
                             condensed: false, numberSize: 0.13, zoneWidth: 0.045,
                             needle: Color(red: 1, green: 0.33, blue: 0.1), fill: Color(white: 0.9),
                             race: false, peakMarker: false, glass: 0.05, dome: false)

    /// B: race dash. Big condensed numbers, high contrast, LED blocks and shift lights.
    static let race = LabLook(id: "B", title: "B · Race dash", bezel: 0.035,
                              bezelTop: Color(white: 0.42), bezelBottom: Color(white: 0.1),
                              faceCenter: Color(white: 0.03), faceEdge: .black, ink: .white,
                              condensed: true, numberSize: 0.2, zoneWidth: 0.06,
                              needle: GaugeColor.red.color, fill: .white,
                              race: true, peakMarker: false, glass: 0.03, dome: false)

    /// C: aftermarket pod gauge. Deep black face, thick dark-metal bezel, backlit white ink, peak marker, domed glass.
    static let aftermarket = LabLook(id: "C", title: "C · Aftermarket gauge", bezel: 0.11,
                                     bezelTop: Color(white: 0.46), bezelBottom: Color(white: 0.06),
                                     faceCenter: Color(white: 0.045), faceEdge: .black, ink: Color(white: 0.96),
                                     condensed: false, numberSize: 0.12, zoneWidth: 0.03,
                                     needle: Color(red: 1, green: 0.27, blue: 0.12), fill: Color(white: 0.95),
                                     race: false, peakMarker: true, glass: 0.1, dome: true)

    static let all = [oem, race, aftermarket]
}

// MARK: - Shared drawing

/// A round gauge's geometry: center, radius and the 260° scale (same angles as the real styles).
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

/// The zones painted on the scale, as fractions: blue below normalLow (when there is one), then GaugeRange's stops
/// past the normal band: yellow from normalHigh, orange from halfway to the redline, red from the redline to max.
private func zones(_ range: GaugeRange) -> [(from: Double, to: Double, color: Color)] {
    let orange = (range.normalHigh + range.redline) / 2
    var values: [(Double, Double, GaugeColor)] = range.normalLow > range.min ? [(range.min, range.normalLow, .blue)] : []
    values += [(range.normalHigh, orange, .yellow), (orange, range.redline, .orange), (range.redline, range.max, .red)]
    return values.map { (range.fraction($0.0), range.fraction($0.1), $0.2.color) }.filter { $0.from < $0.to }
}

/// One color below the redline, red past it (only when there is a red zone).
private func fillColor(_ look: LabLook, _ range: GaugeRange, _ value: Double) -> Color {
    range.redline < range.max && value >= range.redline ? GaugeColor.red.color : look.fill
}

/// Round bezel lit from the top with a darker bottom, then the face, recessed: a soft shadow inside the rim,
/// heavier at the top where the bezel blocks the light. Returns the face radius.
private func drawRoundHousing(_ look: LabLook, _ d: Dial, in ctx: inout GraphicsContext) -> CGFloat {
    let r = d.r
    let top = CGPoint(x: d.center.x, y: d.center.y - r), bottom = CGPoint(x: d.center.x, y: d.center.y + r)
    ctx.fill(d.circle(r), with: .linearGradient(Gradient(colors: [look.bezelTop, look.bezelBottom]), startPoint: top, endPoint: bottom))
    // Inner chamfer, lit the other way, so the ring reads as raised.
    ctx.fill(d.circle(r * (1 - look.bezel * 0.4)),
             with: .linearGradient(Gradient(colors: [look.bezelBottom, look.bezelTop.opacity(0.75)]), startPoint: top, endPoint: bottom))
    let faceR = r * (1 - look.bezel)
    ctx.fill(d.circle(faceR), with: .radialGradient(Gradient(colors: [look.faceCenter, look.faceEdge]),
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
private func drawGlass(_ look: LabLook, clip: Path, top: CGFloat, middle: CGFloat, in ctx: inout GraphicsContext,
                       dome: Path? = nil, size: CGFloat) {
    ctx.drawLayer { layer in
        layer.clip(to: clip)
        let rect = clip.boundingRect
        // Soft edges: a sharp edge would read as a drawn line, not as light on glass.
        layer.addFilter(.blur(radius: size * 0.04))
        layer.fill(Path(ellipseIn: CGRect(x: rect.minX - rect.width * 0.05, y: top - rect.height * 0.3,
                                          width: rect.width * 1.1, height: middle - top + rect.height * 0.3)),
                   with: .linearGradient(Gradient(colors: [.white.opacity(look.glass), .white.opacity(0)]),
                                         startPoint: CGPoint(x: rect.midX, y: top), endPoint: CGPoint(x: rect.midX, y: middle)))
        if look.dome, let dome {
            layer.stroke(dome, with: .color(.white.opacity(look.glass * 1.6)), style: StrokeStyle(lineWidth: size * 0.025, lineCap: .round))
        }
    }
}

// MARK: - Analog

private struct LabAnalog: View {
    let look: LabLook
    let sensor: Sensor
    let range: GaugeRange
    let value: Double
    let peak: Double
    let units: Units

    var body: some View {
        VStack(spacing: GaugeLook.gap) {
            if look.race { ShiftLights(range: range, value: value) }
            Canvas { ctx, size in draw(&ctx, size) }
                .aspectRatio(1, contentMode: .fit)
        }
    }

    private func draw(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let d = Dial(size)
        let f = drawRoundHousing(look, d, in: &ctx)

        // Zones as solid bands on the scale's outer edge.
        for zone in zones(range) {
            ctx.stroke(d.arc(zone.from, zone.to, radius: f * 0.9), with: .color(zone.color), lineWidth: f * look.zoneWidth)
        }

        // Ticks and numbers in the chosen units.
        let display = range.converted(for: sensor, units)
        let scale = DialScale(min: display.min, max: display.max)
        let span = display.max - display.min
        if span > 0 {
            for tick in scale.ticks {
                let at = (tick.value - display.min) / span
                var path = Path()
                path.move(to: d.point(at, f * 0.86))
                path.addLine(to: d.point(at, f * (tick.isMajor ? 0.74 : 0.8)))
                ctx.stroke(path, with: .color(look.ink.opacity(tick.isMajor ? 1 : 0.6)), lineWidth: f * (tick.isMajor ? 0.022 : 0.01))
            }
            let labelRadius = f * (0.72 - look.numberSize * 0.75)
            for tick in scale.ticks where tick.isMajor {
                let at = (tick.value - display.min) / span
                ctx.draw(Text(scale.label(tick.value)).font(look.font(f * look.numberSize)).foregroundStyle(look.ink),
                         at: d.point(at, labelRadius))
            }
        }
        let unit = sensor.displayUnit(units)
        ctx.draw(Text(scale.divisor == 1000 ? "×1000 \(unit)" : unit).font(look.font(f * 0.08)).foregroundStyle(look.ink.opacity(0.6)),
                 at: CGPoint(x: d.center.x, y: d.center.y + f * 0.4))

        if look.peakMarker, peak > range.min {
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
            let place = CGAffineTransform(rotationAngle: d.angle(range.fraction(value)))
                .concatenating(CGAffineTransform(translationX: d.center.x, y: d.center.y))
            layer.fill(needle.applying(place), with: .color(look.needle))
            layer.fill(d.circle(f * 0.085), with: .radialGradient(Gradient(colors: [Color(white: 0.2), .black]),
                                                                  center: CGPoint(x: d.center.x, y: d.center.y - f * 0.03),
                                                                  startRadius: 0, endRadius: f * 0.1))
        }
        ctx.stroke(d.circle(f * 0.085), with: .color(Color(white: 0.3)), lineWidth: max(0.5, f * 0.006))

        var dome = Path()
        dome.addArc(center: d.center, radius: f * 0.86, startAngle: .degrees(205), endAngle: .degrees(250), clockwise: false)
        drawGlass(look, clip: d.circle(f), top: d.center.y - f, middle: d.center.y, in: &ctx, dome: dome, size: f)
    }
}

/// Race dash shift lights: 4 green, 3 yellow, 3 red, lighting up one by one from normalHigh to the redline;
/// all of them flash at the redline.
private struct ShiftLights: View {
    let range: GaugeRange
    let value: Double

    private static let colors: [GaugeColor] = [.green, .green, .green, .green, .yellow, .yellow, .yellow, .red, .red, .red]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.125)) { timeline in
            let flashing = value >= range.redline
            let flashOn = Int(timeline.date.timeIntervalSinceReferenceDate * 8) % 2 == 0
            let span = range.redline - range.normalHigh
            let lit = span > 0 ? Int(((value - range.normalHigh) / span * 10).rounded(.down)) : 0
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

// MARK: - Arc

/// A round pod with the scale as a thick arc: one fill color, or LED blocks for the race dash.
private struct LabArc: View {
    let look: LabLook
    let sensor: Sensor
    let range: GaugeRange
    let value: Double
    let units: Units

    var body: some View {
        Canvas { ctx, size in draw(&ctx, size) }
            .aspectRatio(1, contentMode: .fit)
    }

    private func draw(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let d = Dial(size)
        let f = drawRoundHousing(look, d, in: &ctx)
        let at = range.fraction(value)
        let track = f * 0.13, trackRadius = f * 0.68
        let fill = fillColor(look, range, value)

        for zone in zones(range) {
            ctx.stroke(d.arc(zone.from, zone.to, radius: f * 0.84), with: .color(zone.color), lineWidth: f * look.zoneWidth * 0.8)
        }
        if look.race {
            let count = 26, gap = 0.012
            for index in 0..<count {
                let from = Double(index) / Double(count), to = Double(index + 1) / Double(count)
                let on = (from + to) / 2 <= at
                ctx.stroke(d.arc(from + gap / 2, to - gap / 2, radius: trackRadius),
                           with: .color(on ? fill : Color(white: 0.11)), lineWidth: track)
            }
        } else {
            ctx.stroke(d.arc(0, 1, radius: trackRadius), with: .color(Color(white: 0.1)), lineWidth: track)
            if at > 0 { ctx.stroke(d.arc(0, at, radius: trackRadius), with: .color(fill), lineWidth: track) }
        }

        let display = range.converted(for: sensor, units)
        let ends = [(0.0, display.min), (1.0, display.max)]
        for (end, label) in ends {
            let p = d.point(end, trackRadius)
            ctx.draw(Text(label.formatted(.number.precision(.fractionLength(0)).grouping(.never)))
                        .font(look.font(f * 0.12)).foregroundStyle(look.ink.opacity(0.7)),
                     at: CGPoint(x: p.x, y: p.y + f * 0.17))
        }
        ctx.draw(Text(sensor.text(for: value, units: units)).font(look.font(f * (look.race ? 0.46 : 0.38))).foregroundStyle(look.ink),
                 at: d.center)
        ctx.draw(Text(sensor.displayUnit(units)).font(look.font(f * 0.11)).foregroundStyle(look.ink.opacity(0.6)),
                 at: CGPoint(x: d.center.x, y: d.center.y + f * 0.3))

        var dome = Path()
        dome.addArc(center: d.center, radius: f * 0.86, startAngle: .degrees(205), endAngle: .degrees(250), clockwise: false)
        drawGlass(look, clip: d.circle(f), top: d.center.y - f, middle: d.center.y, in: &ctx, dome: dome, size: f)
    }
}

// MARK: - Bar

/// A rectangular instrument: bezel, recessed face, a vertical track with the zones beside it, ticks, the value below.
private struct LabBar: View {
    let look: LabLook
    let sensor: Sensor
    let range: GaugeRange
    let value: Double
    let units: Units

    var body: some View {
        Canvas { ctx, size in draw(&ctx, size) }
            .aspectRatio(0.62, contentMode: .fit)
    }

    private func draw(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let outer = CGRect(origin: .zero, size: size)
        let side = min(size.width, size.height)
        let corner = side * 0.14
        // Bezel lit from the top, then the recessed face (same recipe as the round housing).
        ctx.fill(Path(roundedRect: outer, cornerRadius: corner),
                 with: .linearGradient(Gradient(colors: [look.bezelTop, look.bezelBottom]),
                                       startPoint: CGPoint(x: outer.midX, y: 0), endPoint: CGPoint(x: outer.midX, y: outer.maxY)))
        let bezel = side / 2 * look.bezel * 1.4
        let face = outer.insetBy(dx: bezel, dy: bezel)
        let facePath = Path(roundedRect: face, cornerRadius: corner - bezel)
        ctx.fill(facePath, with: .linearGradient(Gradient(colors: [look.faceCenter, look.faceEdge]),
                                                 startPoint: CGPoint(x: face.midX, y: face.minY), endPoint: CGPoint(x: face.midX, y: face.maxY)))
        ctx.drawLayer { layer in
            layer.clip(to: facePath)
            layer.addFilter(.blur(radius: side * 0.03))
            var shade = Path(outer.insetBy(dx: -side, dy: -side))
            shade.addPath(Path(roundedRect: face.insetBy(dx: side * 0.02, dy: side * 0.02).offsetBy(dx: 0, dy: side * 0.03),
                               cornerRadius: corner - bezel))
            layer.fill(shade, with: .color(.black.opacity(0.85)), style: FillStyle(eoFill: true))
        }

        // Track: 18 % of the face wide, from near the top to above the value.
        let trackWidth = face.width * 0.18
        let track = CGRect(x: face.midX - trackWidth / 2, y: face.minY + face.height * 0.08,
                           width: trackWidth, height: face.height * 0.66)
        func y(_ fraction: Double) -> CGFloat { track.maxY - track.height * fraction }
        let at = range.fraction(value)
        let fill = fillColor(look, range, value)

        // Zones in a thin strip left of the track.
        let strip = face.width * 0.045
        for zone in zones(range) {
            ctx.fill(Path(CGRect(x: track.minX - strip * 2, y: y(zone.to), width: strip, height: y(zone.from) - y(zone.to))),
                     with: .color(zone.color))
        }
        if look.race {
            let count = 16, gap = track.height * 0.012
            for index in 0..<count {
                let from = Double(index) / Double(count), to = Double(index + 1) / Double(count)
                let on = (from + to) / 2 <= at
                ctx.fill(Path(CGRect(x: track.minX, y: y(to) + gap / 2, width: track.width, height: y(from) - y(to) - gap)),
                         with: .color(on ? fill : Color(white: 0.11)))
            }
        } else {
            ctx.fill(Path(track), with: .color(Color(white: 0.1)))
            ctx.fill(Path(CGRect(x: track.minX, y: y(at), width: track.width, height: track.maxY - y(at))), with: .color(fill))
        }

        // Ticks right of the track; numbers only at both ends.
        let display = range.converted(for: sensor, units)
        let scale = DialScale(min: display.min, max: display.max)
        let span = display.max - display.min
        if span > 0 {
            for tick in scale.ticks {
                let ty = y((tick.value - display.min) / span)
                var path = Path()
                path.move(to: CGPoint(x: track.maxX + strip, y: ty))
                path.addLine(to: CGPoint(x: track.maxX + strip + face.width * (tick.isMajor ? 0.09 : 0.05), y: ty))
                ctx.stroke(path, with: .color(look.ink.opacity(tick.isMajor ? 1 : 0.6)), lineWidth: side * (tick.isMajor ? 0.014 : 0.007))
            }
        }
        for (fraction, label) in [(0.0, display.min), (1.0, display.max)] {
            ctx.draw(Text(label.formatted(.number.precision(.fractionLength(0)).grouping(.never)))
                        .font(look.font(face.width * 0.12)).foregroundStyle(look.ink.opacity(0.7)),
                     at: CGPoint(x: track.maxX + strip + face.width * 0.26, y: y(fraction)))
        }
        let unit = sensor.displayUnit(units)
        ctx.draw(Text("\(Text(sensor.text(for: value, units: units)).font(look.font(face.width * (look.race ? 0.3 : 0.25))))\(Text("\u{2009}" + unit).font(look.font(face.width * 0.1)).foregroundStyle(look.ink.opacity(0.6)))")
                    .foregroundStyle(look.ink),
                 at: CGPoint(x: face.midX, y: face.maxY - face.height * 0.13))

        var dome = Path()
        dome.move(to: CGPoint(x: face.minX + face.width * 0.15, y: face.minY + face.height * 0.06))
        dome.addLine(to: CGPoint(x: face.minX + face.width * 0.15, y: face.minY + face.height * 0.3))
        drawGlass(look, clip: facePath, top: face.minY, middle: face.midY, in: &ctx, dome: dome, size: side)
    }
}

#Preview {
    NavigationStack { GaugeLabView(scanner: BluetoothScanner()) }
}
#endif
