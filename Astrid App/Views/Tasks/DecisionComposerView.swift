//  DecisionComposerView.swift
//  Write a decision from a task's details (ADEV-189): a question, its options, and, if wanted,
//  criteria rated per option in traffic-light colours. Posted as a comment it draws as cards that
//  answer with a tap (`DecisionThread`); added to the description it draws the same, read-only.
//  The draft and its markdown are `DecisionDraft`; this view only edits it.

import AstridCore
import SwiftUI

struct DecisionComposerView: View {
    enum Destination: Hashable { case comment, description }

    /// Hands back the markdown and where it goes; the caller posts or saves it.
    let onDone: (_ markdown: String, _ destination: Destination) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft = DecisionDraft()
    @State private var destination: Destination = .comment

    /// The Form's own text colour (ADEV-228), for the preview and the rating rows. Its rows follow
    /// the system appearance, so the app theme's colours vanished whenever the two disagreed.
    static let previewTextColor: Color = .primary

    var body: some View {
        NavigationStack {
            Form {
                Section(NSLocalizedString("decision_composer.question", comment: "Section: the question")) {
                    TextField(NSLocalizedString("decision_composer.question_placeholder", comment: ""),
                              text: $draft.question, axis: .vertical)
                        .accessibilityIdentifier("decisionComposer.question")
                }
                optionsSection
                criteriaSection
                if draft.criteria.contains(where: { !$0.name.isEmpty }) {
                    ForEach(draft.options.filter { !$0.text.isEmpty }) { option in
                        ratingsSection(option)
                    }
                }
                Section {
                    Picker(NSLocalizedString("decision_composer.post_to", comment: ""), selection: $destination) {
                        Text(NSLocalizedString("decision_composer.as_comment", comment: "")).tag(Destination.comment)
                        Text(NSLocalizedString("decision_composer.in_description", comment: "")).tag(Destination.description)
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text(destination == .comment
                         ? NSLocalizedString("decision_composer.comment_hint", comment: "")
                         : NSLocalizedString("decision_composer.description_hint", comment: ""))
                }
                if draft.problem == nil {
                    Section(NSLocalizedString("decision_composer.preview", comment: "")) {
                        MarkdownText(source: draft.markdown, defaultColor: Self.previewTextColor)
                    }
                }
            }
            .navigationTitle(NSLocalizedString("decision_composer.title", comment: "Ask for a decision"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("actions.cancel", comment: "")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(destination == .comment
                           ? NSLocalizedString("decision_composer.post", comment: "")
                           : NSLocalizedString("decision_composer.add", comment: "")) {
                        onDone(draft.markdown, destination)
                        dismiss()
                    }
                    .disabled(draft.problem != nil)
                    .accessibilityIdentifier("decisionComposer.done")
                }
            }
        }
    }

    // MARK: - Options

    private var optionsSection: some View {
        Section {
            ForEach($draft.options) { $option in
                HStack {
                    TextField(NSLocalizedString("decision_composer.option_placeholder", comment: ""),
                              text: $option.text)
                        .accessibilityIdentifier("decisionComposer.option")
                    Button {
                        draft.recommended = draft.recommended == option.id ? nil : option.id
                    } label: {
                        Image(systemName: draft.recommended == option.id ? "star.fill" : "star")
                            .foregroundColor(Theme.accent)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(Text(NSLocalizedString("decision.recommended", comment: "")))
                }
            }
            .onDelete { offsets in
                guard draft.options.count - offsets.count >= 2 else { return }
                draft.options.remove(atOffsets: offsets)
            }
            Button {
                draft.options.append(.init())
            } label: {
                Label(NSLocalizedString("decision_composer.add_option", comment: ""), systemImage: "plus")
            }
        } header: {
            Text(NSLocalizedString("decision_composer.options", comment: ""))
        } footer: {
            if draft.problem == .tooFewOptions {
                Text(NSLocalizedString("decision_composer.needs_two_options", comment: ""))
            } else {
                Text(NSLocalizedString("decision_composer.recommend_hint", comment: ""))
            }
        }
    }

    // MARK: - Criteria and ratings

    private var criteriaSection: some View {
        Section {
            ForEach($draft.criteria) { $criterion in
                VStack(alignment: .leading, spacing: Theme.spacing8) {
                    TextField(NSLocalizedString("decision_composer.criterion_placeholder", comment: ""),
                              text: $criterion.name)
                        .accessibilityIdentifier("decisionComposer.criterion")
                    if !criterion.name.isEmpty {
                        TextField(NSLocalizedString("decision_composer.criterion_detail_placeholder", comment: ""),
                                  text: $criterion.detail, axis: .vertical)
                            .font(Theme.Typography.callout())
                            .accessibilityIdentifier("decisionComposer.criterionDetail")
                    }
                }
            }
            .onDelete { draft.criteria.remove(atOffsets: $0) }
            if draft.criteria.count < DecisionDraft.maxCriteria {
                Button {
                    draft.criteria.append(.init())
                } label: {
                    Label(NSLocalizedString("decision_composer.add_criterion", comment: ""), systemImage: "plus")
                }
                .accessibilityIdentifier("decisionComposer.addCriterion")
            }
        } header: {
            Text(NSLocalizedString("decision_composer.criteria", comment: ""))
        } footer: {
            Text(NSLocalizedString("decision_composer.criteria_hint", comment: ""))
        }
    }

    private func ratingsSection(_ option: DecisionDraft.Option) -> some View {
        Section {
            ForEach(draft.criteria.filter { !$0.name.isEmpty }) { criterion in
                ratingRow(option: option.id, criterion: criterion)
            }
        } header: {
            Text(option.text)
        } footer: {
            if draft.problem == .reasonWithoutRating {
                Text(NSLocalizedString("decision_composer.reason_needs_colour", comment: ""))
            }
        }
    }

    private func ratingRow(option: UUID, criterion: DecisionDraft.Criterion) -> some View {
        let cell = draft.cell(option: option, criterion: criterion.id)
        return VStack(alignment: .leading, spacing: Theme.spacing8) {
            HStack {
                Text(verbatim: criterion.name).foregroundColor(Self.previewTextColor)
                Spacer()
                ForEach(DecisionGrid.ratingTokens, id: \.self) { token in
                    lightButton(token, selected: cell.rating == token) {
                        let rating = cell.rating == token ? nil : token
                        draft.set(.init(rating: rating, text: cell.text), option: option, criterion: criterion.id)
                    }
                }
            }
            TextField(NSLocalizedString("decision_composer.reason_placeholder", comment: ""),
                      text: Binding(get: { cell.text }, set: {
                          draft.set(.init(rating: draft.cell(option: option, criterion: criterion.id).rating, text: $0),
                                    option: option, criterion: criterion.id)
                      }))
                .font(Theme.Typography.callout())
                .accessibilityIdentifier("decisionComposer.note")
        }
    }

    /// One traffic light: the grid's own colour for the token, ringed when picked; a second tap
    /// clears it.
    private func lightButton(_ token: String, selected: Bool, action: @escaping () -> Void) -> some View {
        let rating = DecisionGrid.rank(of: token).flatMap(TradeOffRating.init(rawValue:))
        return Button(action: action) {
            Circle()
                .fill(rating.map(TradeOffPalette.fill) ?? Color.secondary)
                .frame(width: Theme.spacing24, height: Theme.spacing24)
                .overlay(Circle().strokeBorder(Self.previewTextColor,
                                               lineWidth: selected ? AstridTokens.Size.Comfortable.selectionOutline : 0))
                .opacity(selected ? 1 : AstridTokens.State.disabledOpacity)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(Text(TradeOffPalette.label(for: rating)))
        .accessibilityIdentifier("decisionComposer.light.\(DecisionGrid.rank(of: token) ?? 0)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

extension DecisionComposerView {
    /// The comment bar's menu entry that opens the composer.
    static func menuItem(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(NSLocalizedString("decision_composer.title", comment: "Ask for a decision"), systemImage: "checklist")
        }
        .accessibilityIdentifier("taskDetail.askForDecision")
    }

    /// Post a written decision as a comment, through the Outbox like any other.
    static func post(_ markdown: String, taskId: String) async {
        do {
            _ = try await CommentService.shared.createComment(
                taskId: taskId, content: markdown, type: .MARKDOWN, authorId: AuthManager.shared.userId)
        } catch {
            AppLog.debug("❌ [DecisionComposer] Failed to post decision: \(error) — kept as pending")
        }
        NotificationCenter.default.post(name: .commentDidSync, object: nil, userInfo: ["taskId": taskId])
    }
}
