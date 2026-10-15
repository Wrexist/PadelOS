import SwiftUI
import PadelCore
import PadelStore

/// Full-screen creation flow, laid out as numbered steps on one page: name, format,
/// players, settings, more options. Each step lights up when it is complete; the bottom
/// bar always shows the next thing to do (add players, then start).
struct CreateTournamentFlow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    if let createError {
                        MessageBanner(style: .error, message: createError)
                    }
                    nameStep
                        .staggeredAppear(0)
                    formatStep
                        .staggeredAppear(1)
                    playersStep
                        .staggeredAppear(2)
                    settingsStep
                        .staggeredAppear(3)
                    advancedStep
                        .staggeredAppear(4)
                    issuesSection
                }
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.top, Theme.Spacing.s)
                .padding(.bottom, Theme.Spacing.xl)
            }
            .scrollDismissesKeyboard(.interactively)
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

    // MARK: Steps

    private var nameStep: some View {
        StepCard(number: 1, title: "Tournament name", isComplete: !draft.name.trimmingCharacters(in: .whitespaces).isEmpty) {
            TextField("Tournament name", text: $draft.name)
                .font(.padelHeadline)
                .foregroundStyle(Theme.Colors.textPrimary)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .padding(.horizontal, Theme.Spacing.m)
                .frame(minHeight: 52)
                .background(Theme.Colors.surfaceRaised.opacity(0.7), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityIdentifier("tournamentNameField")
        }
    }

    private var formatStep: some View {
        let columns = dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.flexible(), spacing: Theme.Spacing.s), GridItem(.flexible(), spacing: Theme.Spacing.s)]
        return StepCard(number: 2, title: "Format", isComplete: true) {
            LazyVGrid(columns: columns, spacing: Theme.Spacing.s) {
                ForEach(TournamentFormat.allCases) { format in
                    FormatTile(format: format, isSelected: draft.format == format) {
                        withAnimation(Motion.bouncy.motionSafe) { draft.format = format }
                    }
                }
            }
        }
    }

    private var playersStep: some View {
        StepCard(number: 3, title: draft.format.usesTeams ? "Teams" : "Players", isComplete: !draft.needsMorePlayers) {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                Button {
                    showPlayers = true
                } label: {
                    HStack {
                        ValueRow(symbol: "person.2.fill", title: draft.format.usesTeams ? "Teams" : "Players", value: playersValue)
                        Image(systemName: "chevron.forward")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, Theme.Spacing.m)
                    .frame(minHeight: 52)
                    .background(Theme.Colors.surfaceRaised.opacity(0.7), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
                .accessibilityIdentifier("playersRow")
                if !draft.players.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(draft.players) { player in
                            PlayerChip(name: player.name)
                                .transition(.scale(scale: 0.4).combined(with: .opacity))
                        }
                    }
                    .animation(Motion.bouncy, value: draft.players.map(\.id))
                }
            }
        }
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

    private var settingsStep: some View {
        StepCard(number: 4, title: "Settings", isComplete: true) {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                CountStepper(title: "Courts", symbol: "square.split.2x1", value: $draft.courtCount, range: 1...ConfigurationValidator.maximumCourts)
                    .accessibilityIdentifier("courtsStepper")

                Picker("Scoring", selection: $draft.scoringMode.animation(Motion.smooth.motionSafe)) {
                    ForEach(TournamentDraftModel.ScoringMode.allCases) { Text(verbatim: $0.localizedName).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("scoringModePicker")

                Group {
                    switch draft.scoringMode {
                    case .points:
                        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                            Label("Points per match", systemImage: "trophy")
                                .font(.padelMeta.weight(.semibold))
                                .foregroundStyle(Theme.Colors.textSecondary)
                            PointsChips(options: TournamentDraftModel.pointOptions, selection: $draft.points)
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("pointsPicker")
                    case .timed:
                        CountStepper(title: "Minutes per match", symbol: "timer", value: $draft.minutes, range: 5...60)
                    case .sets:
                        SettingRow(title: "Match format", symbol: "tennisball") {
                            Picker("Match format", selection: $draft.setsRules) {
                                // Presets follow the golden-point toggle so the selection always matches a tag.
                                ForEach(SetsRules.presets.map { preset in
                                    var rules = preset
                                    rules.goldenPoint = draft.setsRules.goldenPoint
                                    return rules
                                }, id: \.self) { Text(verbatim: $0.localizedName).tag($0) }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .accessibilityIdentifier("setsPicker")
                        }
                        Toggle("Golden point at deuce", isOn: $draft.setsRules.goldenPoint)
                            .font(.padelName)
                            .tint(Theme.Colors.accent)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))

                SettingRow(title: "Rounds", symbol: "arrow.triangle.2.circlepath") {
                    Picker("Rounds", selection: $draft.roundsMode.animation(Motion.smooth.motionSafe)) {
                        Text("Auto").tag(TournamentDraftModel.RoundsMode.automatic)
                        Text("Choose").tag(TournamentDraftModel.RoundsMode.manual)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
                if draft.roundsMode == .manual {
                    CountStepper(title: "Number of rounds", symbol: "number", value: $draft.manualRounds, range: 1...ConfigurationValidator.maximumRounds)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                roundsSummary
            }
        }
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
        return HStack(alignment: .top, spacing: Theme.Spacing.s) {
            Image(systemName: "clock")
                .foregroundStyle(Theme.Colors.accentText)
                .accessibilityHidden(true)
            Text(verbatim: detail)
                .font(.padelMeta.weight(.medium))
                .foregroundStyle(Theme.Colors.textSecondary)
                .contentTransition(.numericText())
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("roundsSummary")
        }
        .padding(Theme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .animation(Motion.snappy, value: detail)
    }

    private var advancedStep: some View {
        StepCard(number: 5, title: "More options", isComplete: false, isOptional: true) {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                Button {
                    withAnimation(Motion.smooth.motionSafe) { showAdvanced.toggle() }
                } label: {
                    HStack {
                        Text(showAdvanced ? "Fewer options" : "Playoffs, rest points, draw")
                            .font(.padelMeta.weight(.semibold))
                            .foregroundStyle(Theme.Colors.textSecondary)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .rotationEffect(.degrees(showAdvanced ? 180 : 0))
                    }
                    .frame(minHeight: Theme.minimumTapTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if showAdvanced {
                    VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                        if draft.scoringMode == .points {
                            SettingRow(title: "Points for resting", symbol: "cup.and.saucer") {
                                Picker("Points for resting", selection: $draft.restCompensation) {
                                    ForEach(RestCompensation.allCases, id: \.self) { Text(verbatim: $0.localizedName).tag($0) }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                            }
                        }
                        SettingRow(title: "Playoffs", symbol: "trophy") {
                            Picker("Playoffs", selection: $draft.playoff) {
                                ForEach(PlayoffSize.allCases) { Text(verbatim: $0.localizedName).tag($0) }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .accessibilityIdentifier("playoffPicker")
                        }
                        Toggle("Final round from standings", isOn: $draft.finalRound)
                            .font(.padelName)
                            .tint(Theme.Colors.accent)
                            .disabled(draft.playoff != .none)
                        if draft.finalRound {
                            Text("The last round is arranged from the standings: the top four play together on court 1.")
                                .font(.padelMeta)
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if draft.format == .mexicano {
                            SettingRow(title: "Pairing in each group", symbol: "person.2.wave.2") {
                                Picker("Pairing in each group", selection: $draft.mexicanoPattern) {
                                    ForEach(MexicanoPairingPattern.allCases, id: \.self) { Text(verbatim: $0.localizedName).tag($0) }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                            }
                        }
                        if draft.format.hasFirstRoundOption {
                            SettingRow(title: "First round", symbol: "dice") {
                                Picker("First round", selection: $draft.mexicanoFirstRound) {
                                    ForEach(MexicanoFirstRound.allCases, id: \.self) { Text(verbatim: $0.localizedName).tag($0) }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                            }
                        }
                        if draft.format.usesGroups {
                            TextField("Group A name", text: $draft.mixedLabels.groupA)
                                .textFieldStyle(.roundedBorder)
                            TextField("Group B name", text: $draft.mixedLabels.groupB)
                                .textFieldStyle(.roundedBorder)
                        }
                        Button {
                            draft.seed = UInt64.random(in: 1...UInt64.max)
                        } label: {
                            Label("Shuffle the draw", systemImage: "shuffle")
                        }
                        .buttonStyle(.padelSecondary)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    @ViewBuilder
    private var issuesSection: some View {
        if !draft.players.isEmpty && !draft.issues.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                SectionHeader("Before you start")
                ForEach(draft.issues) { issue in
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Label(issue.message, systemImage: issue.severity == .error ? "exclamationmark.triangle.fill" : "info.circle")
                            .foregroundStyle(issue.severity == .error ? Theme.Colors.danger : Theme.Colors.warning)
                            .font(.padelMeta.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                        if let suggestion = issue.suggestion {
                            Text(verbatim: suggestion)
                                .font(.padelMeta)
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .surfaceCard(highlight: (draft.errors.isEmpty ? Theme.Colors.warning : Theme.Colors.danger).opacity(0.5))
            .transition(.opacity.combined(with: .scale(scale: 0.96)))
        }
    }

    private var primaryButton: some View {
        VStack(spacing: Theme.Spacing.s) {
            if draft.needsMorePlayers {
                Button {
                    showPlayers = true
                } label: {
                    Label("Add Players", systemImage: "person.badge.plus")
                }
                .buttonStyle(.padelPrimary)
                .accessibilityIdentifier("addPlayersButton")
            } else {
                Button(action: create) {
                    Label("Start Tournament", systemImage: "play.fill")
                }
                .buttonStyle(.padelPrimary)
                .disabled(!draft.canCreate)
                .accessibilityIdentifier("startTournamentButton")
            }
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.vertical, Theme.Spacing.m)
        .background { BottomBarFade() }
        .animation(Motion.snappy, value: draft.needsMorePlayers)
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
            withAnimation(Motion.smooth.motionSafe) { createError = error.localizedDescription }
        }
    }
}

// MARK: - Building blocks

/// A numbered step: the number turns into a lime check when the step is complete.
struct StepCard<Content: View>: View {
    let number: Int
    let title: LocalizedStringKey
    var isComplete: Bool
    var isOptional = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(spacing: Theme.Spacing.s) {
                ZStack {
                    Circle()
                        .fill(isComplete ? Theme.Colors.accent : Color.clear)
                    Circle()
                        .strokeBorder(isComplete ? Color.clear : (isOptional ? Theme.Colors.separator : Theme.Colors.accentText), lineWidth: 1.5)
                    if isComplete {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .black))
                            .foregroundStyle(Theme.Colors.onAccent)
                            .transition(.scale.combined(with: .opacity))
                    } else {
                        Text(verbatim: "\(number)")
                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                            .foregroundStyle(isOptional ? Theme.Colors.textSecondary : Theme.Colors.accentText)
                    }
                }
                .frame(width: 24, height: 24)
                .animation(Motion.bouncy, value: isComplete)
                .accessibilityHidden(true)
                Text(title)
                    .font(.padelEyebrow)
                    .tracking(1.1)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .accessibilityAddTraits(.isHeader)
            }
            content()
        }
        .surfaceCard()
    }
}

/// A format as a tile: mini court diagram, name and one-line explanation.
struct FormatTile: View {
    let format: TournamentFormat
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                HStack(alignment: .top) {
                    FormatGlyph(format: format, isSelected: isSelected)
                    Spacer(minLength: 0)
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isSelected ? Theme.Colors.accentText : Theme.Colors.separator)
                        .contentTransition(.symbolEffect(.replace))
                }
                Text(verbatim: format.localizedName)
                    .font(.padelName.weight(.bold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: format.localizedSummary)
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(Theme.Spacing.m)
            .frame(maxWidth: .infinity, minHeight: 148, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isSelected ? Theme.Colors.accent.opacity(0.14) : Theme.Colors.surfaceRaised.opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(isSelected ? Theme.Colors.accentText : Theme.Colors.separator.opacity(0.6), lineWidth: isSelected ? 2 : 1)
            )
            .scaleEffect(isSelected ? 1 : 0.98)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(Text(verbatim: format.localizedName))
        .accessibilityHint(Text(verbatim: format.localizedSummary))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("format-\(format.rawValue)")
    }
}

/// − value + with a rolling number. VoiceOver adjusts it by swiping up or down.
struct CountStepper: View {
    let title: LocalizedStringKey
    let symbol: String
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            Image(systemName: symbol)
                .foregroundStyle(Theme.Colors.accentText)
                .frame(width: 22)
                .accessibilityHidden(true)
            Text(title)
                .font(.padelName)
                .foregroundStyle(Theme.Colors.textPrimary)
            Spacer(minLength: Theme.Spacing.s)
            HStack(spacing: 0) {
                stepButton("minus", enabled: value > range.lowerBound) { value -= 1 }
                Text("\(value)")
                    .font(.padelScoreboard(size: 22))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .contentTransition(.numericText(value: Double(value)))
                    .frame(minWidth: 36)
                stepButton("plus", enabled: value < range.upperBound) { value += 1 }
            }
            .background(Theme.Colors.surfaceRaised.opacity(0.7), in: Capsule())
        }
        .animation(Motion.snappy, value: value)
        .sensoryFeedback(.selection, trigger: value)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text("\(value)"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: if value < range.upperBound { value += 1 }
            case .decrement: if value > range.lowerBound { value -= 1 }
            @unknown default: break
            }
        }
    }

    private func stepButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.bold))
                .foregroundStyle(enabled ? Theme.Colors.textPrimary : Theme.Colors.textSecondary.opacity(0.5))
                .frame(width: Theme.minimumTapTarget, height: Theme.minimumTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .disabled(!enabled)
    }
}

/// Points-per-match options as chips; the lime pill slides to the selection.
struct PointsChips: View {
    let options: [Int]
    @Binding var selection: Int
    @Namespace private var pill

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            ForEach(options, id: \.self) { option in
                Button {
                    withAnimation(Motion.bouncy.motionSafe) { selection = option }
                } label: {
                    Text("\(option)")
                        .font(.padelScoreboard(size: 20))
                        .foregroundStyle(selection == option ? Theme.Colors.onAccent : Theme.Colors.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background {
                            if selection == option {
                                Capsule()
                                    .fill(Theme.Colors.accent)
                                    .matchedGeometryEffect(id: "pill", in: pill)
                            } else {
                                Capsule().fill(Theme.Colors.surfaceRaised.opacity(0.7))
                            }
                        }
                }
                .buttonStyle(.pressable)
                .accessibilityLabel(Text(ScoringRule.totalPoints(option).localizedName))
                .accessibilityAddTraits(selection == option ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// Icon and title on the leading side, a control (usually a menu picker) trailing.
struct SettingRow<Control: View>: View {
    let title: LocalizedStringKey
    let symbol: String
    @ViewBuilder let control: () -> Control

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            Image(systemName: symbol)
                .foregroundStyle(Theme.Colors.accentText)
                .frame(width: 22)
                .accessibilityHidden(true)
            Text(title)
                .font(.padelName)
                .foregroundStyle(Theme.Colors.textPrimary)
            Spacer(minLength: Theme.Spacing.s)
            control()
                .tint(Theme.Colors.accentText)
        }
        .frame(minHeight: Theme.minimumTapTarget)
    }
}
