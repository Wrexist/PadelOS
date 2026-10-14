import SwiftUI
import PadelCore
import PadelStore

/// Full-screen creation flow: settings form → players → create.
struct CreateTournamentFlow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var draft: TournamentDraftModel
    @State private var showPlayers = false
    @State private var showAdvanced = false
    @State private var createError: String?
    let onCreated: (Tournament) -> Void

    init(quickAmericano: Bool, onCreated: @escaping (Tournament) -> Void) {
        self.onCreated = onCreated
        _draft = State(initialValue: TournamentDraftModel())
        self.quickAmericano = quickAmericano
    }

    private let quickAmericano: Bool
    @State private var didConfigure = false

    var body: some View {
        NavigationStack {
            Form {
                if let createError {
                    Section {
                        MessageBanner(style: .error, message: createError)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                }
                nameSection
                formatSection
                playersSection
                settingsSection
                advancedSection
                issuesSection
            }
            .scrollContentBackground(.hidden)
            .screenBackground()
            .navigationTitle("Create Tournament")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("cancelCreateButton")
                }
            }
            .safeAreaInset(edge: .bottom) { primaryButton }
            .navigationDestination(isPresented: $showPlayers) {
                PlayersEditorView(draft: draft)
            }
        }
        .onAppear(perform: configureOnce)
    }

    private func configureOnce() {
        guard !didConfigure else { return }
        didConfigure = true
        let settings = model.settings.settings
        draft = quickAmericano ? TournamentDraftModel.quickAmericano(settings: settings) : TournamentDraftModel(settings: settings)
        if quickAmericano && draft.players.count < 4 { showPlayers = true }
    }

    // MARK: Sections

    private var nameSection: some View {
        Section {
            TextField("Tournament name", text: $draft.name)
                .font(.padelName)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .accessibilityIdentifier("tournamentNameField")
        } header: {
            Text("Tournament name")
        }
        .listRowBackground(Theme.Colors.surface)
    }

    private var formatSection: some View {
        Section("Format") {
            ForEach(TournamentFormat.allCases) { format in
                Button {
                    draft.format = format
                } label: {
                    HStack(spacing: Theme.Spacing.m) {
                        Image(systemName: draft.format == format ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(draft.format == format ? Theme.Colors.accentText : Theme.Colors.textSecondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(format.localizedName)
                                .font(.padelName)
                                .foregroundStyle(Theme.Colors.textPrimary)
                            Text(format.localizedSummary)
                                .font(.padelMeta)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(draft.format == format ? .isSelected : [])
                .accessibilityIdentifier("format-\(format.rawValue)")
            }
        }
        .listRowBackground(Theme.Colors.surface)
    }

    private var playersSection: some View {
        Section {
            Button {
                showPlayers = true
            } label: {
                HStack {
                    ValueRow(symbol: "person.2", title: draft.format.usesTeams ? "Teams" : "Players", value: playersValue)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("playersRow")
            if !draft.players.isEmpty {
                Text(draft.players.map(\.name).joined(separator: ", "))
                    .font(.padelMeta)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(2)
            }
        }
        .listRowBackground(Theme.Colors.surface)
    }

    private var playersValue: String {
        if draft.format.usesTeams {
            return String(localized: "\(draft.teams.count) teams")
        }
        if draft.format.usesGroups {
            return "\(draft.count(in: .a)) + \(draft.count(in: .b))"
        }
        return String(localized: "\(draft.players.count) players")
    }

    private var settingsSection: some View {
        Section {
            Stepper(value: $draft.courtCount, in: 1...ConfigurationValidator.maximumCourts) {
                ValueRow(symbol: "square.split.2x1", title: "Courts", value: "\(draft.courtCount)")
            }
            .accessibilityIdentifier("courtsStepper")

            Picker("Scoring", selection: $draft.scoringMode) {
                ForEach(TournamentDraftModel.ScoringMode.allCases) { Text($0.localizedName).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("scoringModePicker")

            switch draft.scoringMode {
            case .points:
                Picker(selection: $draft.points) {
                    ForEach(TournamentDraftModel.pointOptions, id: \.self) { Text("\($0) points").tag($0) }
                } label: {
                    Label("Points per match", systemImage: "trophy")
                        .foregroundStyle(Theme.Colors.textPrimary)
                }
                .accessibilityIdentifier("pointsPicker")
            case .timed:
                Stepper(value: $draft.minutes, in: 5...60, step: 1) {
                    ValueRow(symbol: "timer", title: "Minutes per match", value: "\(draft.minutes)")
                }
            case .sets:
                Picker(selection: $draft.setsRules) {
                    // Presets follow the golden-point toggle so the selection always matches a tag.
                    ForEach(SetsRules.presets.map { preset in
                        var rules = preset
                        rules.goldenPoint = draft.setsRules.goldenPoint
                        return rules
                    }, id: \.self) { Text($0.localizedName).tag($0) }
                } label: {
                    Label("Match format", systemImage: "tennisball")
                        .foregroundStyle(Theme.Colors.textPrimary)
                }
                .accessibilityIdentifier("setsPicker")
                Toggle("Golden point at deuce", isOn: $draft.setsRules.goldenPoint)
            }

            Picker(selection: $draft.roundsMode) {
                Text("Auto").tag(TournamentDraftModel.RoundsMode.automatic)
                Text("Choose").tag(TournamentDraftModel.RoundsMode.manual)
            } label: {
                Label("Rounds", systemImage: "arrow.triangle.2.circlepath")
                    .foregroundStyle(Theme.Colors.textPrimary)
            }
            .pickerStyle(.menu)

            if draft.roundsMode == .manual {
                Stepper(value: $draft.manualRounds, in: 1...ConfigurationValidator.maximumRounds) {
                    ValueRow(symbol: "number", title: "Number of rounds", value: "\(draft.manualRounds)")
                }
            }
            roundsSummary
        } header: {
            Text("Settings")
        }
        .listRowBackground(Theme.Colors.surface)
    }

    private var roundsSummary: some View {
        let hours = draft.estimatedMinutes / 60
        let minutes = draft.estimatedMinutes % 60
        let duration = hours > 0 ? String(localized: "\(hours) h \(minutes) min") : String(localized: "\(minutes) min")
        var detail = draft.playoff == .none
            ? String(localized: "\(draft.roundCount) rounds · about \(duration)")
            : String(localized: "\(draft.roundCount) rounds + \(draft.playoff.localizedName) · about \(duration)")
        if draft.format.hasPrecomputedSchedule && draft.fullRotationRounds > 1 {
            detail += draft.roundCount >= draft.fullRotationRounds
                ? String(localized: " · full rotation")
                : String(localized: " · full rotation needs \(draft.fullRotationRounds)")
        }
        return Text(detail)
            .font(.padelMeta)
            .foregroundStyle(Theme.Colors.textSecondary)
            .accessibilityIdentifier("roundsSummary")
    }

    private var advancedSection: some View {
        Section {
            DisclosureGroup("More options", isExpanded: $showAdvanced) {
                if draft.scoringMode == .points {
                    Picker("Points for resting", selection: $draft.restCompensation) {
                        ForEach(RestCompensation.allCases, id: \.self) { Text($0.localizedName).tag($0) }
                    }
                }
                Picker("Playoffs", selection: $draft.playoff) {
                    ForEach(PlayoffSize.allCases) { Text($0.localizedName).tag($0) }
                }
                .accessibilityIdentifier("playoffPicker")
                Toggle("Final round from standings", isOn: $draft.finalRound)
                    .disabled(draft.playoff != .none)
                if draft.format == .mexicano {
                    Picker("Pairing in each group", selection: $draft.mexicanoPattern) {
                        ForEach(MexicanoPairingPattern.allCases, id: \.self) { Text($0.localizedName).tag($0) }
                    }
                }
                if draft.format.hasFirstRoundOption {
                    Picker("First round", selection: $draft.mexicanoFirstRound) {
                        ForEach(MexicanoFirstRound.allCases, id: \.self) { Text($0.localizedName).tag($0) }
                    }
                }
                if draft.format.usesGroups {
                    TextField("Group A name", text: $draft.mixedLabels.groupA)
                    TextField("Group B name", text: $draft.mixedLabels.groupB)
                }
                Button("Shuffle the draw") {
                    draft.seed = UInt64.random(in: 1...UInt64.max)
                }
            }
            .tint(Theme.Colors.textPrimary)
        } footer: {
            if draft.finalRound {
                Text("The last round is arranged from the standings: the top four play together on court 1.")
            }
        }
        .listRowBackground(Theme.Colors.surface)
    }

    @ViewBuilder
    private var issuesSection: some View {
        if !draft.players.isEmpty && !draft.issues.isEmpty {
            Section {
                ForEach(draft.issues) { issue in
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Label(issue.message, systemImage: issue.severity == .error ? "exclamationmark.triangle.fill" : "info.circle")
                            .foregroundStyle(issue.severity == .error ? Theme.Colors.danger : Theme.Colors.warning)
                            .font(.padelMeta.weight(.medium))
                        if let suggestion = issue.suggestion {
                            Text(suggestion)
                                .font(.padelMeta)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            } header: {
                Text("Before you start")
            }
            .listRowBackground(Theme.Colors.surface)
        }
    }

    private var primaryButton: some View {
        VStack(spacing: Theme.Spacing.s) {
            if draft.needsMorePlayers {
                Button("Add Players") { showPlayers = true }
                    .buttonStyle(.padelPrimary)
                    .accessibilityIdentifier("addPlayersButton")
            } else {
                Button("Start Tournament", action: create)
                    .buttonStyle(.padelPrimary)
                    .disabled(!draft.canCreate)
                    .accessibilityIdentifier("startTournamentButton")
            }
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.vertical, Theme.Spacing.m)
        .background(.bar)
    }

    private func create() {
        do {
            let tournament = try model.store.create(draft.draft)
            model.settings.update { settings in
                settings.rememberNames(draft.players.map(\.name))
                settings.defaultFormat = draft.format
                settings.defaultCourtCount = draft.courtCount
                if draft.scoringMode == .points { settings.defaultPoints = draft.points }
            }
            onCreated(tournament)
        } catch {
            createError = error.localizedDescription
        }
    }
}
