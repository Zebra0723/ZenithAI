import SwiftUI
import ZenithCore

/// Zenith's look. Zenith is time, so the app is the sky: a gradient that follows the hour
/// (night, dawn, day, dusk), stars when it's dark, a warm glow on the horizon, and glass
/// panels floating on it. One colour is Zenith's own, the sun, for whatever is live.
/// Every Galaxy member has its colour, so a timeline reads at a glance.
///
/// Type: New York Light for headlines (time is a long story, told well), SF Pro for
/// reading, thin SF numerals for every time and percentage (a watch face), SF Mono for
/// what the machines say.
enum Theme {
    // Ink on the sky
    static let ink = Color(red: 0.957, green: 0.945, blue: 0.918)          // #F4F1EA
    static let ink2 = ink.opacity(0.66)
    static let ink3 = ink.opacity(0.42)
    static let ink4 = ink.opacity(0.22)

    // Glass
    static let glass = Color.white.opacity(0.055)
    static let glassStrong = Color.white.opacity(0.095)
    static let glassHover = Color.white.opacity(0.08)
    static let line = Color.white.opacity(0.09)
    static let lineStrong = Color.white.opacity(0.17)
    static let shade = Color.black.opacity(0.22)

    /// The sun. What's live, and nothing else.
    static let sun = Color(red: 0.949, green: 0.706, blue: 0.353)          // #F2B45A
    static let sunSoft = Color(red: 0.961, green: 0.780, blue: 0.494)      // #F5C77E
    static let sunGlow = sun.opacity(0.35)

    static let alert = Color(red: 0.969, green: 0.490, blue: 0.420)        // #F77D6B
    static let good = Color(red: 0.494, green: 0.851, blue: 0.659)         // #7ED9A8
    static let calm = Color(red: 0.443, green: 0.800, blue: 0.886)         // #71CCE2

    // MARK: Type

    /// Headlines: New York, light, large.
    static func display(_ size: CGFloat, weight: Font.Weight = .light) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
    static func title(_ size: CGFloat = 15, weight: Font.Weight = .semibold) -> Font { .system(size: size, weight: weight) }
    static func body(_ size: CGFloat = 13.5, weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight) }
    static func mono(_ size: CGFloat = 12, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
    /// Times and percentages: thin, like a watch face.
    static func numeral(_ size: CGFloat, weight: Font.Weight = .thin) -> Font {
        .system(size: size, weight: weight).monospacedDigit()
    }

    // MARK: Colour by meaning

    static func color(_ member: Member) -> Color {
        switch member {
        case .zenith: return sun
        case .cloud: return Color(red: 0.498, green: 0.698, blue: 1.0)      // #7FB2FF
        case .nova: return Color(red: 0.612, green: 0.549, blue: 1.0)       // #9C8CFF
        case .comet: return Color(red: 0.435, green: 0.839, blue: 0.910)    // #6FD6E8
        case .nebula: return Color(red: 0.561, green: 0.937, blue: 0.835)   // #8FEFD5
        case .orbit: return Color(red: 0.941, green: 0.604, blue: 0.722)    // #F09AB8
        }
    }

    static func color(_ column: BoardColumn) -> Color {
        switch column {
        case .forecast: return ink2
        case .working: return sun
        case .needsYou: return alert
        case .done: return good
        case .living: return calm
        }
    }

    static func color(_ status: MissionStatus) -> Color {
        switch status {
        case .failed: return alert
        case .stopped, .paused, .queued: return ink3
        default: return color(Mission.columnFor(status))
        }
    }
}

extension Mission {
    static func columnFor(_ status: MissionStatus) -> BoardColumn {
        var m = Mission(title: "", brief: "")
        m.status = status
        return m.column
    }
}

// MARK: - The sky

/// The hour's sky: its colours, and how much of the night shows.
struct SkyPalette {
    var top: Color
    var middle: Color
    var horizon: Color
    var glow: Double
    var stars: Double

    static func at(_ date: Date) -> SkyPalette {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        let h = Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60
        func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r / 255, green: g / 255, blue: b / 255) }
        switch h {
        case 5..<8: // Dawn
            return SkyPalette(top: rgb(12, 16, 38), middle: rgb(36, 32, 72), horizon: rgb(104, 66, 92), glow: 0.55, stars: 0.25)
        case 8..<17: // Day: still a deep sky, so type stays crisp
            return SkyPalette(top: rgb(10, 22, 46), middle: rgb(20, 42, 76), horizon: rgb(44, 78, 112), glow: 0.22, stars: 0)
        case 17..<21: // Dusk
            return SkyPalette(top: rgb(11, 14, 36), middle: rgb(40, 30, 64), horizon: rgb(112, 64, 58), glow: 0.6, stars: 0.35)
        default: // Night
            return SkyPalette(top: rgb(6, 8, 20), middle: rgb(12, 17, 44), horizon: rgb(28, 30, 70), glow: 0.18, stars: 1)
        }
    }

    static func partOfDay(_ date: Date) -> String {
        let h = Calendar.current.component(.hour, from: date)
        switch h {
        case 5..<12: return "morning"
        case 12..<17: return "afternoon"
        case 17..<21: return "evening"
        default: return "night"
        }
    }
}

/// The window's ground: the sky at this hour, redrawn every few minutes.
struct SkyBackground: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 300)) { ctx in
            let p = SkyPalette.at(ctx.date)
            ZStack {
                LinearGradient(stops: [
                    .init(color: p.top, location: 0),
                    .init(color: p.middle, location: 0.62),
                    .init(color: p.horizon, location: 1),
                ], startPoint: .top, endPoint: .bottom)
                StarField(opacity: p.stars)
                // The horizon glow.
                GeometryReader { geo in
                    Ellipse()
                        .fill(RadialGradient(colors: [Theme.sun.opacity(p.glow), .clear], center: .center,
                                             startRadius: 0, endRadius: geo.size.width * 0.45))
                        .frame(width: geo.size.width * 1.2, height: geo.size.height * 0.5)
                        .position(x: geo.size.width * 0.55, y: geo.size.height * 1.08)
                        .blur(radius: 40)
                }
            }
            .animation(.easeInOut(duration: 2), value: p.stars)
        }
        .ignoresSafeArea()
    }
}

/// Faint stars, always in the same places.
struct StarField: View {
    var opacity: Double

    private struct Star {
        let x: Double
        let y: Double
        let r: Double
        let a: Double
    }

    /// Positions as fractions of the window, from a fixed seed.
    private static let stars: [Star] = {
        var seed: UInt64 = 0x5EED_2E41_7A11
        func next() -> Double {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(seed >> 11) / 9_007_199_254_740_992.0
        }
        var list: [Star] = []
        for _ in 0..<170 {
            let x = next()
            let y = pow(next(), 1.4) * 0.75
            let r = 0.4 + next() * 1.1
            let a = 0.15 + next() * 0.55
            list.append(Star(x: x, y: y, r: r, a: a))
        }
        return list
    }()

    var body: some View {
        Canvas { context, size in
            draw(&context, size)
        }
        .allowsHitTesting(false)
    }

    private func draw(_ context: inout GraphicsContext, _ size: CGSize) {
        guard opacity > 0 else { return }
        let w = Double(size.width)
        let h = Double(size.height)
        for star in Self.stars {
            let fade: Double = 1 - star.y / 0.9
            let alpha: Double = star.a * opacity * fade
            let rect = CGRect(x: star.x * w, y: star.y * h, width: star.r * 2, height: star.r * 2)
            context.fill(Path(ellipseIn: rect), with: .color(Color.white.opacity(alpha)))
        }
    }
}

// MARK: - Glass

struct GlassModifier: ViewModifier {
    var radius: CGFloat = 18
    var tint: Color? = nil
    var strong = false

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(strong ? Theme.glassStrong : Theme.glass)
                    .background(.ultraThinMaterial.opacity(0.35), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [(tint ?? .white).opacity(tint == nil ? 0.16 : 0.55),
                                                          (tint ?? .white).opacity(tint == nil ? 0.05 : 0.18)],
                                                 startPoint: .top, endPoint: .bottom), lineWidth: 1)
            }
            .shadow(color: (tint ?? .black).opacity(tint == nil ? 0.18 : 0.22), radius: tint == nil ? 18 : 22, y: tint == nil ? 8 : 0)
    }
}

extension View {
    func glass(radius: CGFloat = 18, tint: Color? = nil, strong: Bool = false) -> some View {
        modifier(GlassModifier(radius: radius, tint: tint, strong: strong))
    }
}

/// A glass panel.
struct Panel<Content: View>: View {
    var padding: CGFloat = 22
    var tint: Color? = nil
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glass(tint: tint)
    }
}

// MARK: - Structure

/// The top of every page: the moment, a large serif headline, a line of explanation,
/// and the clock.
struct PageTitle<Trailing: View>: View {
    let eyebrow: String
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .bottom, spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                Eyebrow(eyebrow)
                Text(title)
                    .font(Theme.display(40))
                    .tracking(-0.8)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle {
                    Text(subtitle)
                        .font(Theme.body(14))
                        .lineSpacing(3)
                        .foregroundStyle(Theme.ink2)
                        .frame(maxWidth: 620, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            trailing
        }
    }
}

extension PageTitle where Trailing == EmptyView {
    init(eyebrow: String, title: String, subtitle: String? = nil) {
        self.init(eyebrow: eyebrow, title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// Spaced capitals above a group.
struct Eyebrow: View {
    let text: String
    var color: Color = Theme.ink3
    init(_ text: String, color: Color = Theme.ink3) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(2)
            .foregroundStyle(color)
    }
}

/// The time, in thin numerals: Zenith's signature, top right of the board.
struct Clock: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            VStack(alignment: .trailing, spacing: 6) {
                Text(ctx.date.formatted(.dateTime.hour(.defaultDigits(amPM: .omitted)).minute()))
                    .font(Theme.numeral(46, weight: .ultraLight))
                    .tracking(-1)
                    .foregroundStyle(Theme.ink)
                Text(ctx.date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.ink3)
            }
        }
    }
}

struct Rule: View {
    var color: Color = Theme.line
    var body: some View { Rectangle().fill(color).frame(height: 1) }
}

/// A scrolling page with Zenith's margins.
struct Page<Content: View>: View {
    var maxWidth: CGFloat = 1000
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) { content }
                .padding(.horizontal, 48)
                .padding(.top, 54)
                .padding(.bottom, 52)
                .frame(maxWidth: maxWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
    }
}

/// An empty state: the mark, a line, and what to do.
struct EmptyState: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 14) {
            ZenithGlyph(live: true).frame(width: 34, height: 34).opacity(0.85)
            Text(title).font(Theme.display(22)).foregroundStyle(Theme.ink)
            Text(detail).font(Theme.body(13.5)).lineSpacing(3).foregroundStyle(Theme.ink2)
                .multilineTextAlignment(.center).frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

// MARK: - Controls

struct ZenithButtonStyle: ButtonStyle {
    enum Kind { case primary, quiet, alert }
    var kind: Kind = .quiet
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 16)
            .frame(height: 32)
            .background(background(configuration.isPressed), in: Capsule())
            .overlay(Capsule().strokeBorder(kind == .primary ? Color.white.opacity(0.35) : Theme.lineStrong, lineWidth: kind == .primary ? 0.5 : 1))
            .shadow(color: kind == .primary && isEnabled ? Theme.sunGlow : .clear, radius: 14, y: 2)
            .opacity(isEnabled ? 1 : 0.38)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .contentShape(Capsule())
    }

    private var foreground: Color {
        switch kind {
        case .primary: return Color(red: 0.10, green: 0.07, blue: 0.03)
        case .quiet: return Theme.ink
        case .alert: return Theme.alert
        }
    }

    private func background(_ pressed: Bool) -> AnyShapeStyle {
        switch kind {
        case .primary:
            return AnyShapeStyle(LinearGradient(colors: [Theme.sunSoft, Theme.sun], startPoint: .top, endPoint: .bottom))
        case .quiet, .alert:
            return AnyShapeStyle(pressed ? Theme.glassStrong : Theme.glass)
        }
    }
}

/// A round icon button on glass.
struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.ink)
            .frame(width: 32, height: 32)
            .background(configuration.isPressed ? Theme.glassStrong : Theme.glass, in: Circle())
            .overlay(Circle().strokeBorder(Theme.lineStrong, lineWidth: 1))
            .contentShape(Circle())
    }
}

struct ZenithField: ViewModifier {
    var mono = false
    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .font(mono ? Theme.mono(12.5) : Theme.body(13.5))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.lineStrong, lineWidth: 1))
    }
}

extension View {
    func zenithField(mono: Bool = false) -> some View { modifier(ZenithField(mono: mono)) }
}

/// A switch: the sun rises in it when it's on.
struct ZenithToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Button { isOn.toggle() } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule().fill(isOn ? Theme.sun.opacity(0.28) : Color.black.opacity(0.3))
                Capsule().strokeBorder(isOn ? Theme.sun.opacity(0.6) : Theme.lineStrong, lineWidth: 1)
                Circle()
                    .fill(isOn ? Theme.sun : Theme.ink3)
                    .shadow(color: isOn ? Theme.sunGlow : .clear, radius: 6)
                    .padding(3.5)
            }
            .frame(width: 40, height: 23)
            .animation(.spring(response: 0.28, dampingFraction: 0.8), value: isOn)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isOn ? "On" : "Off")
    }
}

/// A small rounded label.
struct Pill: View {
    let text: String
    var color: Color = Theme.ink2

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .frame(height: 21)
            .background(color.opacity(0.13), in: Capsule())
            .overlay(Capsule().strokeBorder(color.opacity(0.25), lineWidth: 0.5))
    }
}

/// A member's name with their colour.
struct MemberTag: View {
    let member: Member
    var short = true

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(Theme.color(member)).frame(width: 6, height: 6)
                .shadow(color: Theme.color(member).opacity(0.7), radius: 3)
            Text(short && member == .cloud ? "Cloud" : member.name)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.ink2)
        }
    }
}

struct StatusPill: View {
    let mission: Mission
    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(Theme.color(mission.status)).frame(width: 6, height: 6)
                .shadow(color: Theme.color(mission.status).opacity(0.8), radius: 4)
            Text(Prompts.phrase(mission.status).sentenceCased)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.ink)
        }
        .padding(.horizontal, 11)
        .frame(height: 25)
        .background(Theme.glass, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.lineStrong, lineWidth: 1))
    }
}

/// A thin progress line that glows where it's lit.
struct Meter: View {
    var value: Double
    var color: Color = Theme.sun
    var height: CGFloat = 3

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                Capsule().fill(color)
                    .frame(width: max(0, min(1, value)) * geo.size.width)
                    .shadow(color: color.opacity(0.7), radius: 4)
            }
        }
        .frame(height: height)
    }
}

/// A ring gauge from 0 to 100%, with the cap marked and the reading in thin numerals.
struct SunDial: View {
    var value: Double          // 0...1
    var cap: Double            // 0...1
    var lineWidth: CGFloat = 10
    var label: String
    var caption: String

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            ZStack {
                Circle().stroke(Color.white.opacity(0.07), lineWidth: lineWidth)
                Circle()
                    .trim(from: 0, to: max(0.002, min(value, 1)))
                    .stroke(value >= cap ? Theme.alert : Theme.sun, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: Theme.sunGlow, radius: 10)
                // The cap.
                Capsule()
                    .fill(Theme.ink)
                    .frame(width: 2, height: lineWidth + 10)
                    .offset(y: -side / 2)
                    .rotationEffect(.degrees(360 * cap))
                VStack(spacing: 4) {
                    Text(label).font(Theme.numeral(side * 0.24, weight: .ultraLight)).tracking(-1).foregroundStyle(Theme.ink)
                    Text(caption.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(1.6).foregroundStyle(Theme.ink3)
                }
            }
            .frame(width: side, height: side)
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

/// The sun, breathing: something is working right now.
struct PulseDot: View {
    var color: Color = Theme.sun
    @State private var on = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .shadow(color: color, radius: 4)
            .background(Circle().fill(color.opacity(0.3)).scaleEffect(on ? 2.6 : 1).opacity(on ? 0 : 1))
            .onAppear {
                withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) { on = true }
            }
    }
}

// MARK: - The mark

/// Zenith's mark: the horizon as a shallow arc, a line rising from it, and the sun at the
/// top of that line: the highest point of the sky.
struct ZenithGlyph: View {
    var live = false

    var body: some View {
        Canvas { context, size in
            let s = min(size.width, size.height)
            let ox = (size.width - s) / 2, oy = (size.height - s) / 2
            let stroke = max(1.2, s * 0.07)
            var horizon = Path()
            horizon.move(to: CGPoint(x: ox + s * 0.06, y: oy + s * 0.88))
            horizon.addQuadCurve(to: CGPoint(x: ox + s * 0.94, y: oy + s * 0.88), control: CGPoint(x: ox + s * 0.5, y: oy + s * 0.70))
            context.stroke(horizon, with: .color(Theme.ink), style: StrokeStyle(lineWidth: stroke, lineCap: .round))
            var rise = Path()
            rise.move(to: CGPoint(x: ox + s * 0.5, y: oy + s * 0.70))
            rise.addLine(to: CGPoint(x: ox + s * 0.5, y: oy + s * 0.42))
            context.stroke(rise, with: .color(Theme.ink.opacity(0.5)), style: StrokeStyle(lineWidth: stroke * 0.75, lineCap: .round))
            let d = s * 0.3
            let sun = CGRect(x: ox + s * 0.5 - d / 2, y: oy + s * 0.04, width: d, height: d)
            if live {
                context.fill(Path(ellipseIn: sun.insetBy(dx: -d * 0.5, dy: -d * 0.5)), with: .color(Theme.sun.opacity(0.18)))
            }
            context.fill(Path(ellipseIn: sun), with: .color(live ? Theme.sun : Theme.ink))
        }
    }
}

// MARK: - Formatting

extension String {
    /// "needs you" → "Needs you".
    var sentenceCased: String { prefix(1).uppercased() + dropFirst() }
}

enum Format {
    static func percent(_ value: Double) -> String {
        value < 10 ? String(format: "%.1f%%", value) : String(format: "%.0f%%", value)
    }

    static func tokens(_ value: Int) -> String {
        switch value {
        case 1_000_000...: return String(format: "%.1fM", Double(value) / 1_000_000)
        case 1_000...: return String(format: "%.1fK", Double(value) / 1_000)
        default: return "\(value)"
        }
    }

    static func hours(_ h: Double) -> String {
        if h < 1 { return "\(max(5, Int((h * 60).rounded())))m" }
        if h < 48 { return h == h.rounded() ? "\(Int(h))h" : String(format: "%.1fh", h) }
        return String(format: "%.0f days", h / 24)
    }

    static func elapsed(_ seconds: TimeInterval) -> String {
        let s = Int(max(0, seconds))
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m" }
        if s < 86_400 { return "\(s / 3600)h \(s % 3600 / 60)m" }
        return "\(s / 86_400)d \(s % 86_400 / 3600)h"
    }

    static func time(_ date: Date) -> String { date.formatted(date: .omitted, time: .shortened) }

    static func date(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "Today, " + time(date) }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday, " + time(date) }
        if Calendar.current.isDateInTomorrow(date) { return "Tomorrow, " + time(date) }
        return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
    }
}
