import SwiftUI
import ZenithCore

/// Every question every mission is waiting on, answered in one place, one batch per mission.
struct NeedsYouView: View {
    @ObservedObject var navigation: Navigation
    @ObservedObject private var store = Store.shared

    private var waiting: [Mission] {
        store.missions.filter { ($0.status == .needsYou || $0.status == .living) && !$0.openQuestions.isEmpty }
    }

    var body: some View {
        Page(maxWidth: 900) {
            PageTitle(eyebrow: "Needs you", title: waiting.isEmpty ? "Nothing waits on you." : "Your answers, in one batch.",
                      subtitle: "Missions finish everything they can first, then wait here with all their questions at once. Yes-or-no questions can also be answered with a thumbs up or down to Nebula.")
            if waiting.isEmpty {
                Panel(padding: 0) {
                    EmptyState(title: "All clear", detail: "When a mission needs a decision only you can make, it shows up here. Nothing is sent to you until a mission is done.")
                }
            }
            ForEach(waiting) { m in
                MissionQuestions(mission: m, navigation: navigation)
            }
        }
    }
}

private struct MissionQuestions: View {
    let mission: Mission
    @ObservedObject var navigation: Navigation
    @ObservedObject private var commander = Commander.shared
    @State private var drafts: [String: String] = [:]

    private var questions: [Question] { mission.questions.filter { !$0.applied } }

    private var answered: Int {
        questions.filter { !(drafts[$0.id] ?? $0.answer ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
    }

    private var complete: Bool { answered == questions.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    Eyebrow(mission.status == .living ? "Living mission" : "\(mission.steps.filter { $0.status == .done }.count) of \(mission.steps.count) steps done",
                            color: Theme.alert)
                    Text(mission.title).font(Theme.display(26)).tracking(-0.4)
                }
                Spacer()
                Button { navigation.open(mission.id) } label: {
                    HStack(spacing: 5) {
                        Text("Open mission")
                        Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .bold))
                    }
                    .font(.system(size: 11.5, weight: .medium)).foregroundStyle(Theme.ink3)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 28)
            .padding(.top, 26)
            .padding(.bottom, 10)

            ForEach(Array(questions.enumerated()), id: \.element.id) { i, q in
                if i > 0 { Rule().padding(.horizontal, 28) }
                QuestionRow(number: i + 1, question: q, answer: binding(q))
                    .padding(.horizontal, 28)
                    .padding(.vertical, 22)
            }

            HStack(spacing: 14) {
                Text("\(answered) of \(questions.count)").font(Theme.numeral(15, weight: .light)).foregroundStyle(Theme.ink2)
                Meter(value: questions.isEmpty ? 0 : Double(answered) / Double(questions.count), height: 2).frame(width: 120)
                Text(complete ? "Zenith picks back up the moment you send these." : "Answer each one, then send them together.")
                    .font(Theme.body(12)).foregroundStyle(Theme.ink3)
                Spacer()
                Button {
                    for q in questions {
                        if let d = drafts[q.id] { commander.answer(mission.id, question: q.id, d) }
                    }
                    if mission.status == .living {
                        commander.settleLivingQuestions(mission.id)
                    } else {
                        commander.submitAnswers(mission.id)
                    }
                    drafts = [:]
                } label: {
                    Label("Send answers", systemImage: "arrow.up")
                }
                .buttonStyle(ZenithButtonStyle(kind: .primary))
                .disabled(!complete)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(Color.black.opacity(0.16))
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .glass(radius: 24)
    }

    private func binding(_ q: Question) -> Binding<String> {
        Binding(get: { drafts[q.id] ?? q.answer ?? "" }, set: { drafts[q.id] = $0 })
    }
}

private struct QuestionRow: View {
    let number: Int
    let question: Question
    @Binding var answer: String

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            Text(String(format: "%02d", number))
                .font(Theme.numeral(22, weight: .ultraLight))
                .foregroundStyle(Theme.ink3)
                .frame(width: 34, alignment: .leading)
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Pill(text: question.reason.label, color: color)
                    Text(Format.date(question.askedAt)).font(.system(size: 11)).foregroundStyle(Theme.ink3)
                }
                Text(question.text).font(Theme.display(19)).lineSpacing(3).foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                switch question.kind {
                case .yesNo:
                    HStack(spacing: 10) {
                        choice("Yes", icon: "hand.thumbsup.fill")
                        choice("No", icon: "hand.thumbsdown.fill")
                    }
                case .choice:
                    Options(options: question.options, selected: $answer)
                case .text:
                    TextField("Your answer", text: $answer, axis: .vertical)
                        .lineLimit(1...5)
                        .zenithField()
                }
            }
        }
    }

    private var color: Color {
        switch question.reason {
        case .spend, .publish, .contact: return Theme.alert
        case .install: return Theme.calm
        case .info: return Theme.ink2
        }
    }

    private func choice(_ value: String, icon: String) -> some View {
        let on = answer == value
        return Button { answer = value } label: {
            Label(value, systemImage: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(on ? Color(red: 0.1, green: 0.07, blue: 0.03) : Theme.ink)
                .padding(.horizontal, 20)
                .frame(height: 36)
                .background(on ? AnyShapeStyle(Theme.sun) : AnyShapeStyle(Theme.glass), in: Capsule())
                .overlay(Capsule().strokeBorder(on ? Color.clear : Theme.lineStrong, lineWidth: 1))
                .shadow(color: on ? Theme.sunGlow : .clear, radius: 10)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.12), value: on)
    }
}

/// Options as a list; one is chosen.
private struct Options: View {
    let options: [String]
    @Binding var selected: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(options, id: \.self) { option in
                let on = selected == option
                Button { selected = option } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle().strokeBorder(on ? Theme.sun : Theme.lineStrong, lineWidth: 1.2)
                            if on { Circle().fill(Theme.sun).padding(4).shadow(color: Theme.sun, radius: 3) }
                        }
                        .frame(width: 16, height: 16)
                        Text(option).font(Theme.body(13.5)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(on ? Theme.glassStrong : Color.black.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(on ? Theme.sun.opacity(0.5) : Theme.line, lineWidth: 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
