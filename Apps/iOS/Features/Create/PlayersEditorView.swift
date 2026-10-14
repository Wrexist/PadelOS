import SwiftUI
import UIKit
import PadelCore
import PadelStore

/// Fast player entry: type a name and press return, paste a list, or tap a recent name.
struct PlayersEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Bindable var draft: TournamentDraftModel
    @State private var newName = ""
    @State private var feedback: String?
    @State private var showPaste = false
    @FocusState private var nameFieldFocused: Bool

    var body: some View {
        List {
            entrySection
            suggestionsSection
            playersSection
        }
        .scrollContentBackground(.hidden)
        .screenBackground()
        .navigationTitle(draft.format == .teamAmericano ? "Add Teams" : "Add Players")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                EditButton().disabled(draft.players.isEmpty)
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: Theme.Spacing.s) {
                Button {
                    showPaste = true
                } label: {
                    Label("Add Multiple Players", systemImage: "list.bullet.clipboard")
                }
                .buttonStyle(.padelSecondary)
                .accessibilityIdentifier("addMultipleButton")
                Button("Continue") { dismiss() }
                    .buttonStyle(.padelPrimary)
                    .accessibilityIdentifier("playersContinueButton")
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.vertical, Theme.Spacing.m)
            .background(.bar)
        }
        .sheet(isPresented: $showPaste) {
            PasteNamesSheet { text in
                let result = draft.addMultiple(text)
                feedback = result.skipped.isEmpty
                    ? "Added \(result.added) player\(result.added == 1 ? "" : "s")."
                    : "Added \(result.added). Already in the list: \(result.skipped.joined(separator: ", "))."
            }
        }
        .onAppear { nameFieldFocused = draft.players.isEmpty }
    }

    private var entrySection: some View {
        Section {
            HStack(spacing: Theme.Spacing.m) {
                TextField("Add player name…", text: $newName)
                    .font(.padelName)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .focused($nameFieldFocused)
                    .onSubmit(add)
                    .accessibilityIdentifier("playerNameField")
                Button(action: add) {
                    Image(systemName: "plus")
                        .font(.body.weight(.bold))
                        .foregroundStyle(Theme.Colors.onAccent)
                        .frame(width: 36, height: 36)
                        .background(Theme.Colors.accent, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityLabel("Add player")
                .accessibilityIdentifier("addPlayerButton")
            }
            if draft.format == .mixedAmericano {
                Picker("Group for new players", selection: $draft.nextGroup) {
                    Text(draft.mixedLabels.groupA).tag(PlayerGroup.a)
                    Text(draft.mixedLabels.groupB).tag(PlayerGroup.b)
                }
                .pickerStyle(.segmented)
            }
            if let feedback {
                Text(feedback)
                    .font(.padelMeta)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        } footer: {
            if draft.format == .teamAmericano {
                Text("Players are paired in the order entered: 1 & 2, 3 & 4, … Drag to change teams.")
            }
        }
        .listRowBackground(Theme.Colors.surface)
    }

    @ViewBuilder
    private var suggestionsSection: some View {
        let suggestions = draft.suggestions(from: model.settings.settings.recentPlayerNames)
        if !suggestions.isEmpty {
            Section("Recent players") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Spacing.s) {
                        ForEach(suggestions, id: \.self) { name in
                            Button {
                                draft.addPlayer(named: name)
                            } label: {
                                PlayerChip(name: name, detail: "+")
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Add \(name)")
                        }
                    }
                    .padding(.vertical, Theme.Spacing.xs)
                }
            }
            .listRowBackground(Theme.Colors.surface)
        }
    }

    private var playersSection: some View {
        Section {
            if draft.players.isEmpty {
                Text("No players yet")
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            ForEach(Array(draft.players.enumerated()), id: \.element.id) { index, player in
                HStack(spacing: Theme.Spacing.m) {
                    PlayerAvatar(name: player.name)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(player.name)
                            .font(.padelName)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        if draft.format == .teamAmericano {
                            Text("Team \(index / 2 + 1)")
                                .font(.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                    }
                    Spacer()
                    if draft.format == .mixedAmericano {
                        Menu {
                            Button(draft.mixedLabels.groupA) { draft.setGroup(.a, for: player.id) }
                            Button(draft.mixedLabels.groupB) { draft.setGroup(.b, for: player.id) }
                        } label: {
                            Text(player.group == .b ? draft.mixedLabels.groupB : draft.mixedLabels.groupA)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, Theme.Spacing.s)
                                .padding(.vertical, Theme.Spacing.xs)
                                .background(Theme.Colors.surfaceRaised, in: Capsule())
                        }
                        .accessibilityLabel("Group for \(player.name)")
                    }
                    Button {
                        draft.removePlayer(player.id)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .frame(width: Theme.minimumTapTarget, height: Theme.minimumTapTarget)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(player.name)")
                }
            }
            .onMove { draft.movePlayers(fromOffsets: $0, toOffset: $1) }
            .onDelete { offsets in
                for index in offsets.sorted(by: >) { draft.removePlayer(draft.players[index].id) }
            }
        } header: {
            Text(playersHeader)
        }
        .listRowBackground(Theme.Colors.surface)
    }

    private var playersHeader: String {
        switch draft.format {
        case .teamAmericano: "Players (\(draft.players.count)) · \(draft.teams.count) teams"
        case .mixedAmericano: "\(draft.mixedLabels.groupA) \(draft.count(in: .a)) · \(draft.mixedLabels.groupB) \(draft.count(in: .b))"
        default: "Players (\(draft.players.count))"
        }
    }

    private func add() {
        switch draft.addPlayer(named: newName) {
        case .added:
            feedback = nil
            newName = ""
        case .duplicate(let name):
            feedback = "\(name) is already in the list. Add an initial to tell them apart."
        case .full:
            feedback = "The maximum is \(ConfigurationValidator.maximumPlayers) players."
        case .empty:
            break
        }
        nameFieldFocused = true
    }
}

struct PasteNamesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    let onAdd: (String) -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                Text("One name per line, or separated by commas.")
                    .font(.padelMeta)
                    .foregroundStyle(Theme.Colors.textSecondary)
                TextEditor(text: $text)
                    .font(.padelName)
                    .scrollContentBackground(.hidden)
                    .padding(Theme.Spacing.s)
                    .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.medium))
                    .accessibilityLabel("Player names")
                    .accessibilityIdentifier("pasteNamesEditor")
                Button {
                    if let clipboard = UIPasteboard.general.string { text += (text.isEmpty ? "" : "\n") + clipboard }
                } label: {
                    Label("Paste from Clipboard", systemImage: "doc.on.clipboard")
                }
                .buttonStyle(.padelSecondary)
            }
            .padding(Theme.Spacing.l)
            .screenBackground()
            .navigationTitle("Add Multiple")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd(text)
                        dismiss()
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("pasteAddButton")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
