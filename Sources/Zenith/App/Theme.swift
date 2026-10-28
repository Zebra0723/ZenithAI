import SwiftUI
import ZenithCore

/// Zenith's look: an observatory. Porcelain pages under a midnight sidebar, graphite type,
/// and one colour, the amber of the sun at its highest point, kept for what's live:
/// the working mission, the meter, the active member. SF Pro Expanded for headlines,
/// SF Pro for reading, SF Mono for every number, so time and usage line up like instruments.
enum Theme {
    // Pages
    static let ground = Color(red: 0.953, green: 0.957, blue: 0.965)       // #F3F4F6
    static let surface = Color.white
    static let raised = Color(red: 0.973, green: 0.976, blue: 0.984)       // #F8F9FB
    static let line = Color(red: 0.890, green: 0.902, blue: 0.925)         // #E3E6EC
    static let lineStrong = Color(red: 0.804, green: 0.824, blue: 0.859)   // #CDD2DB

    static let ink = Color(red: 0.067, green: 0.078, blue: 0.106)          // #11141B
    static let ink2 = Color(red: 0.357, green: 0.384, blue: 0.447)         // #5B6272
    static let ink3 = Color(red: 0.565, green: 0.592, blue: 0.651)         // #9097A6

    // The sidebar
    static let night = Color(red: 0.055, green: 0.071, blue: 0.125)        // #0E1220
    static let nightRaised = Color(red: 0.102, green: 0.125, blue: 0.200)  // #1A2033
    static let nightLine = Color(red: 0.149, green: 0.176, blue: 0.259)    // #262D42
    static let nightInk = Color(red: 0.910, green: 0.918, blue: 0.941)     // #E8EAF0
    static let nightInk2 = Color(red: 0.541, green: 0.569, blue: 0.647)    // #8A91A5

    /// The sun. What's live, and nothing else.
    static let sun = Color(red: 0.878, green: 0.627, blue: 0.227)          // #E0A03A
    /// The sun as text on porcelain, where the bright one wouldn't read.
    static let sunDeep = Color(red: 0.639, green: 0.416, blue: 0.075)      // #A36A13
    static let sunWash = Color(red: 0.988, green: 0.957, blue: 0.898)      // #FCF4E5

    static let alert = Color(red: 0.788, green: 0.322, blue: 0.220)        // #C95238
    static let good = Color(red: 0.204, green: 0.537, blue: 0.396)         // #348965
    static let calm = Color(red: 0.180, green: 0.443, blue: 0.533)         // #2E7188

    static func display(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight).width(.expanded)
    }
    static func body(_ size: CGFloat = 13.5, weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight) }
    static func mono(_ size: CGFloat = 12, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
    static func numeral(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static func color(_ column: BoardColumn) -> Color {
        switch column {
        case .forecast: return ink3
        case .working: return sun
        case .needsYou: return alert
        case .done: return good
        case .living: return calm
        }
    }

    static func color(_ status: MissionStatus) -> Color {
        switch status {
        case .failed: return alert
        case .stopped: return ink3
        case .paused, .queued: return ink2
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

// MARK: - Structure

/// The top of every page: spaced capitals, a wide headline, a line of explanation.
struct PageTitle<Trailing: View>: View {
    let eyebrow: String
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .bottom, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                Eyebrow(eyebrow)
                Text(title)
                    .font(Theme.display(28))
                    .tracking(-0.4)
                    .foregroundStyle(Theme.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(Theme.body(13.5))
                        .foregroundStyle(Theme.ink2)
                        .frame(maxWidth: 600, alignment: .leading)
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

struct Eyebrow: View {
    let text: String
    var color: Color = Theme.ink3
    init(_ text: String, color: Color = Theme.ink3) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10.5, weight: .semibold))
            .tracking(1.4)
            .foregroundStyle(color)
    }
}

/// A white panel on the porcelain ground.
struct Panel<Content: View>: View {
    var padding: CGFloat = 20
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
    }
}

struct Rule: View {
    var color: Color = Theme.line
    var body: some View { Rectangle().fill(color).frame(height: 1) }
}

/// A scrolling page with Zenith's margins.
struct Page<Content: View>: View {
    var maxWidth: CGFloat = 980
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) { content }
                .padding(.horizontal, 44)
                .padding(.top, 50)
                .padding(.bottom, 44)
                .frame(maxWidth: maxWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
    }
}

/// An empty state: a quiet mark, a line, and what to do.
struct EmptyState: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 12) {
            ZenithGlyph(live: false).frame(width: 30, height: 30).opacity(0.5)
            Text(title).font(Theme.display(15)).foregroundStyle(Theme.ink)
            Text(detail).font(Theme.body(13)).foregroundStyle(Theme.ink2)
                .multilineTextAlignment(.center).frame(maxWidth: 380)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 56)
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
            .padding(.horizontal, 14)
            .frame(height: 30)
            .background(background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(kind == .primary ? Color.clear : Theme.lineStrong, lineWidth: 1))
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
            .contentShape(Rectangle())
    }

    private var foreground: Color {
        switch kind {
        case .primary: return .white
        case .quiet: return Theme.ink
        case .alert: return Theme.alert
        }
    }

    private var background: Color { kind == .primary ? Theme.ink : Theme.surface }
}

struct ZenithField: ViewModifier {
    var mono = false
    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .font(mono ? Theme.mono(12.5) : Theme.body(13.5))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.lineStrong, lineWidth: 1))
    }
}

extension View {
    func zenithField(mono: Bool = false) -> some View { modifier(ZenithField(mono: mono)) }
}

/// A switch in Zenith's colours.
struct ZenithToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Button { isOn.toggle() } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule().fill(isOn ? Theme.ink : Theme.lineStrong)
                Circle().fill(isOn ? Theme.sun : Color.white).padding(3)
            }
            .frame(width: 36, height: 21)
            .animation(.easeOut(duration: 0.15), value: isOn)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isOn ? "On" : "Off")
    }
}

/// A small rounded label: a status, a member, a model.
struct Pill: View {
    let text: String
    var color: Color = Theme.ink2
    var filled = false

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(filled ? Color.white : color)
            .padding(.horizontal, 8)
            .frame(height: 20)
            .background(filled ? color : color.opacity(0.10), in: Capsule())
    }
}

struct StatusPill: View {
    let mission: Mission
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(Theme.color(mission.status)).frame(width: 6, height: 6)
            Text(Prompts.phrase(mission.status).sentenceCased)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.ink2)
        }
        .padding(.horizontal, 9)
        .frame(height: 22)
        .background(Theme.raised, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1))
    }
}

/// A thin progress line.
struct Meter: View {
    var value: Double
    var color: Color = Theme.sun
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.line)
                Capsule().fill(color).frame(width: max(0, min(1, value)) * geo.size.width)
            }
        }
        .frame(height: height)
    }
}

// MARK: - The mark

/// Zenith's mark: the horizon as a shallow arc, a line rising from it, and the sun at the
/// top of that line: the highest point of the sky.
struct ZenithGlyph: View {
    var live = false
    var onNight = false

    var body: some View {
        Canvas { context, size in
            let s = min(size.width, size.height)
            let ox = (size.width - s) / 2, oy = (size.height - s) / 2
            let stroke = max(1.2, s * 0.075)
            let base = onNight ? Theme.nightInk : Theme.ink
            var horizon = Path()
            horizon.move(to: CGPoint(x: ox + s * 0.06, y: oy + s * 0.86))
            horizon.addQuadCurve(to: CGPoint(x: ox + s * 0.94, y: oy + s * 0.86), control: CGPoint(x: ox + s * 0.5, y: oy + s * 0.70))
            context.stroke(horizon, with: .color(base), style: StrokeStyle(lineWidth: stroke, lineCap: .round))
            var rise = Path()
            rise.move(to: CGPoint(x: ox + s * 0.5, y: oy + s * 0.76))
            rise.addLine(to: CGPoint(x: ox + s * 0.5, y: oy + s * 0.34))
            context.stroke(rise, with: .color(base.opacity(0.55)), style: StrokeStyle(lineWidth: stroke * 0.8, lineCap: .round))
            let d = s * 0.30
            let sunRect = CGRect(x: ox + s * 0.5 - d / 2, y: oy + s * 0.04, width: d, height: d)
            context.fill(Path(ellipseIn: sunRect), with: .color(live ? Theme.sun : base))
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
