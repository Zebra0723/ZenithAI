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
        Page(maxWidth: 860) {
            PageTitle(eyebrow: "Needs you", title: waiting.isEmpty ? "Nothing waiting on you" : "Your answers, in one batch",
                      subtitle: "Missions finish everything they can first, then wait here with all their questions at once. Yes-or-no questions can also be answered with a thumbs up or down to Nebula.")
            if waiting.isEmpty {
                Panel { EmptyState(title: "All clear", detail: "When a mission needs a decision only you can make, it shows up here. Nothing is sent to you until a mission is done.") }
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

    private var complete: Bool {
        questions.allSatisfy { q in
            !(drafts[q.id] ?? q.answer ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(mission.title).font(Theme.display(17))
                    Text(mission.status == .living ? "Living mission" : "\(mission.steps.filter { $0.status == .done }.count) of \(mission.steps.count) steps done")
                        .font(Theme.body(12)).foregroundStyle(Theme.ink2)
                }
                Spacer()
                Button("Open mission") { navigation.open(mission.id) }
                    .buttonStyle(.plain).font(.system(size: 11.5, weight: .medium)).foregroundStyle(Theme.ink2)
            }
            .padding(20)

            ForEach(questions) { q in
                Rule()
                QuestionRow(question: q, answer: binding(q))
                    .padding(20)
            }

            Rule()
            HStack {
                Text(complete ? "Zenith picks back up the moment you send these." : "Answer each one, then send them together.")
                    .font(Theme.body(12)).foregroundStyle(Theme.ink2)
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
            .padding(20)
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
    }

    private func binding(_ q: Question) -> Binding<String> {
        Binding(get: { drafts[q.id] ?? q.answer ?? "" }, set: { drafts[q.id] = $0 })
    }
}

private struct QuestionRow: View {
    let question: Question
    @Binding var answer: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Pill(text: question.reason.label, color: color)
                Text(Format.date(question.askedAt)).font(Theme.mono(10)).foregroundStyle(Theme.ink3)
            }
            Text(question.text).font(Theme.body(14)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
            switch question.kind {
            case .yesNo:
                HStack(spacing: 8) {
                    choice("Yes", icon: "hand.thumbsup")
                    choice("No", icon: "hand.thumbsdown")
                }
            case .choice:
                FlowChoices(options: question.options, selected: $answer)
            case .text:
                TextField("Your answer", text: $answer, axis: .vertical)
                    .lineLimit(1...5)
                    .zenithField()
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
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(on ? Color.white : Theme.ink)
                .padding(.horizontal, 16)
                .frame(height: 32)
                .background(on ? Theme.ink : Theme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(on ? Color.clear : Theme.lineStrong, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Options as a row of buttons; one is chosen.
private struct FlowChoices: View {
    let options: [String]
    @Binding var selected: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(options, id: \.self) { option in
                Button { selected = option } label: {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle().strokeBorder(selected == option ? Theme.ink : Theme.lineStrong, lineWidth: 1.2)
                            if selected == option { Circle().fill(Theme.ink).padding(3.5) }
                        }
                        .frame(width: 15, height: 15)
                        Text(option).font(Theme.body(13)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(selected == option ? Theme.raised : Theme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
