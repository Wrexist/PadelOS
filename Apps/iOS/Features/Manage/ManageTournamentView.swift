import SwiftUI
import PadelCore
import PadelStore

struct ManageTournamentView: View {
    @Environment(AppModel.self) private var model
    @Environment(TournamentStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let tournamentID: TournamentID
    /// Called after the tournament was deleted.
    let onDeleted: () -> Void

    @State private var name = ""
    @State private var courts = 1
    @State private var rounds = 1
    @State private var newPlayer = ""
    @State private var newPlayerGroup: PlayerGroup = .a
    @State private var newTeamFirst = ""
    @State private var newTeamSecond = ""
    @State private var message: String?
    @State private var pendingWithdrawal: WithdrawalTarget?
    @State private var confirmRestart = false
    @State private var confirmDelete = false
    @State private var loaded = false

    enum WithdrawalTarget: Identifiable {
        case player(Player)
        case team(Team)
        var id: String {
            switch self {
            case .player(let p): p.id.description
            case .team(let t): t.id.description
            }
        }
        var name: String {
            switch self {
            case .player(let p): p.name
            case .team(let t): t.name
            }
        }
    }

    var body: some View {
        NavigationStack {
            if let tournament = store.tournament(tournamentID) {
                form(tournament)
            } else {
                EmptyStateView(symbol: "trash", title: "Deleted", message: "This tournament no longer exists.")
            }
        }
    }

    @ViewBuilder
    private func form(_ tournament: Tournament) -> some View {
        let editable = tournament.status == .active
        Form {
            if let message {
                Section {
                    Text(message)
                        .font(.padelMeta)
                        .foregroundStyle(Theme.Colors.textPrimary)
                }
                .listRowBackground(Theme.Colors.surfaceRaised)
            }

            Section("Name") {
                TextField("Tournament name", text: $name)
                    .submitLabel(.done)
                    .onSubmit { apply { try $0.rename(name, now: $1.now) } }
                if name.trimmingCharacters(in: .whitespaces) != tournament.name {
                    Button("Save Name") { apply { try $0.rename(name, now: $1.now) } }
                }
            }
            .listRowBackground(Theme.Colors.surface)

            Section {
                Stepper("Courts: \(courts)", value: $courts, in: 1...ConfigurationValidator.maximumCourts)
                Stepper("Rounds: \(rounds)", value: $rounds, in: max(1, tournament.startedRoundCount)...ConfigurationValidator.maximumRounds)
                if courts != tournament.configuration.courtCount || rounds != tournament.configuration.roundCount {
                    Button("Apply Schedule Changes") {
                        apply { try $0.updateSettings(courtCount: courts, roundCount: rounds, context: $1) }
                    }
                    .fontWeight(.semibold)
                }
                Picker("Playoffs", selection: Binding(
                    get: { tournament.configuration.playoff },
                    set: { value in apply { try $0.updateSettings(playoff: value, context: $1) } }
                )) {
                    ForEach(PlayoffSize.allCases) { Text($0.localizedName).tag($0) }
                }
                Toggle("Final round from standings", isOn: Binding(
                    get: { tournament.configuration.standingsBasedFinalRound },
                    set: { value in apply { try $0.updateSettings(standingsBasedFinalRound: value, context: $1) } }
                ))
                if case .totalPoints = tournament.configuration.scoring {
                    Picker("Points for resting", selection: Binding(
                        get: { tournament.configuration.restCompensation },
                        set: { value in apply { try $0.updateSettings(restCompensation: value, context: $1) } }
                    )) {
                        ForEach(RestCompensation.allCases, id: \.self) { Text($0.localizedName).tag($0) }
                    }
                }
            } header: {
                Text("Schedule")
            } footer: {
                Text("Played rounds and results are always kept. Only rounds that have not started are rebuilt.")
            }
            .listRowBackground(Theme.Colors.surface)
            .disabled(!editable)

            participantsSection(tournament, editable: editable)

            Section("Tournament") {
                if tournament.status == .active {
                    Button("Finish Tournament") {
                        apply { $0.finish(now: $1.now) }
                    }
                } else {
                    Button("Reopen Tournament") {
                        apply { $0.reopen(context: $1) }
                    }
                }
                Button("Restart Tournament…", role: .destructive) { confirmRestart = true }
                Button("Delete Tournament…", role: .destructive) { confirmDelete = true }
                    .accessibilityIdentifier("deleteTournamentButton")
            }
            .listRowBackground(Theme.Colors.surface)

            Section("Fairness") {
                let metrics = ScheduleMetrics.of(tournament)
                if tournament.configuration.format.isIndividual {
                    ValueRow(symbol: "person.2", title: "Repeated partners", value: "\(metrics.partnerRepeats)")
                }
                ValueRow(symbol: "arrow.left.arrow.right", title: "Most meetings of one pair", value: "\(metrics.maxTimesOpposed)")
                ValueRow(symbol: "figure.walk", title: "Matches per player", value: metrics.minPlayed == metrics.maxPlayed ? "\(metrics.minPlayed)" : "\(metrics.minPlayed)–\(metrics.maxPlayed)")
            }
            .listRowBackground(Theme.Colors.surface)
        }
        .scrollContentBackground(.hidden)
        .screenBackground()
        .navigationTitle("Manage")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            name = tournament.name
            courts = tournament.configuration.courtCount
            rounds = tournament.configuration.roundCount
        }
        .confirmationDialog("Withdraw \(pendingWithdrawal?.name ?? "")?", isPresented: Binding(get: { pendingWithdrawal != nil }, set: { if !$0 { pendingWithdrawal = nil } }), titleVisibility: .visible) {
            Button("Withdraw", role: .destructive) {
                guard let target = pendingWithdrawal else { return }
                switch target {
                case .player(let player): apply { try $0.withdrawPlayer(player.id, context: $1) }
                case .team(let team): apply { try $0.withdrawTeam(team.id, context: $1) }
                }
                pendingWithdrawal = nil
            }
        } message: {
            Text("Results already played are kept. Rounds that have not started are rebuilt without them.")
        }
        .confirmationDialog("Restart the tournament?", isPresented: $confirmRestart, titleVisibility: .visible) {
            Button("Restart With Same Draw", role: .destructive) {
                apply { $0.restart(context: $1) }
            }
            Button("Restart With New Draw", role: .destructive) {
                apply { $0.restart(newSeed: UInt64.random(in: 1...UInt64.max), context: $1) }
            }
        } message: {
            Text("Every score and result in this tournament will be cleared. This cannot be undone.")
        }
        .confirmationDialog("Delete \(tournament.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Tournament", role: .destructive) {
                if model.run({ try store.delete(tournamentID) }) {
                    onDeleted()
                }
            }
        } message: {
            Text("The tournament and all results are removed from this iPhone. This cannot be undone.")
        }
    }

    @ViewBuilder
    private func participantsSection(_ tournament: Tournament, editable: Bool) -> some View {
        if tournament.configuration.format.usesTeams {
            Section("Teams") {
                ForEach(tournament.teams) { team in
                    let withdrawn = tournament.withdrawnTeamIDs.contains(team.id)
                    HStack {
                        Text(team.name).foregroundStyle(withdrawn ? Theme.Colors.textSecondary : Theme.Colors.textPrimary)
                        Spacer()
                        if withdrawn {
                            Text("Withdrawn").font(.caption).foregroundStyle(Theme.Colors.textSecondary)
                        } else if editable {
                            Button("Withdraw") { pendingWithdrawal = .team(team) }
                                .font(.padelMeta)
                                .foregroundStyle(Theme.Colors.danger)
                        }
                    }
                }
                if editable {
                    TextField("Player 1", text: $newTeamFirst)
                    TextField("Player 2", text: $newTeamSecond)
                    Button("Add Team") {
                        let first = newTeamFirst, second = newTeamSecond
                        apply { try $0.addTeam(name: "\(first) & \(second)", playerNames: [first, second], context: $1) }
                        newTeamFirst = ""
                        newTeamSecond = ""
                    }
                    .disabled(newTeamFirst.trimmingCharacters(in: .whitespaces).isEmpty || newTeamSecond.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .listRowBackground(Theme.Colors.surface)
        } else {
            Section {
                ForEach(tournament.players) { player in
                    let withdrawn = tournament.withdrawnPlayerIDs.contains(player.id)
                    HStack {
                        PlayerAvatar(name: player.name, size: 26)
                        Text(player.name).foregroundStyle(withdrawn ? Theme.Colors.textSecondary : Theme.Colors.textPrimary)
                        if let group = player.group, tournament.configuration.format.usesGroups {
                            Text(tournament.configuration.mixedLabels.label(for: group))
                                .font(.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                        Spacer()
                        if withdrawn {
                            Text("Withdrawn").font(.caption).foregroundStyle(Theme.Colors.textSecondary)
                        } else if editable {
                            Button("Withdraw") { pendingWithdrawal = .player(player) }
                                .font(.padelMeta)
                                .foregroundStyle(Theme.Colors.danger)
                        }
                    }
                }
                if editable {
                    HStack {
                        TextField("Add a late player", text: $newPlayer)
                            .submitLabel(.done)
                        if tournament.configuration.format.usesGroups {
                            Picker("Group", selection: $newPlayerGroup) {
                                Text(tournament.configuration.mixedLabels.groupA).tag(PlayerGroup.a)
                                Text(tournament.configuration.mixedLabels.groupB).tag(PlayerGroup.b)
                            }
                            .labelsHidden()
                        }
                        Button("Add") {
                            let name = newPlayer, group = newPlayerGroup
                            apply { try $0.addPlayer(name: name, group: group, context: $1) }
                            newPlayer = ""
                        }
                        .disabled(newPlayer.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            } header: {
                Text("Players")
            } footer: {
                Text("A late player joins from the next round that has not started.")
            }
            .listRowBackground(Theme.Colors.surface)
        }
    }

    private func apply(_ change: @escaping (inout Tournament, EngineContext) throws -> Void) {
        do {
            try store.perform(tournamentID) { (t, c) throws(TournamentError) in
                do {
                    try change(&t, c)
                } catch let error as TournamentError {
                    throw error
                } catch {
                    throw TournamentError.notAllowed(error.localizedDescription)
                }
            }
            message = nil
        } catch {
            message = error.localizedDescription
        }
        if let tournament = store.tournament(tournamentID) {
            courts = tournament.configuration.courtCount
            rounds = tournament.configuration.roundCount
        }
    }
}

struct ConflictsView: View {
    @Environment(TournamentStore.self) private var store
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let tournamentID: TournamentID

    var body: some View {
        NavigationStack {
            List {
                if let tournament = store.tournament(tournamentID) {
                    Section {
                        Text("These score changes were recorded on Apple Watch but conflicted with changes already saved on this iPhone. The iPhone's result was kept. Correct any match from its scoring screen if needed.")
                            .font(.padelMeta)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    ForEach(tournament.allMatches.filter { !$0.openConflicts.isEmpty }) { match in
                        Section("Round \(match.roundNumber) · Court \(match.court) · now \(match.score.a)–\(match.score.b)") {
                            ForEach(match.openConflicts) { conflict in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(describe(conflict.event.kind, tournament: tournament, match: match))
                                        .font(.padelName)
                                    Text(conflict.reason.description)
                                        .font(.padelMeta)
                                        .foregroundStyle(Theme.Colors.textSecondary)
                                    Text(conflict.event.timestamp, style: .time)
                                        .font(.caption)
                                        .foregroundStyle(Theme.Colors.textSecondary)
                                }
                            }
                        }
                    }
                    let orphaned = tournament.orphanedConflicts.filter { !$0.isAcknowledged }
                    if !orphaned.isEmpty {
                        Section("Matches no longer in the schedule") {
                            Text("\(orphaned.count) change\(orphaned.count == 1 ? "" : "s") belonged to a round that was rebuilt.")
                                .font(.padelMeta)
                        }
                    }
                }
            }
            .navigationTitle("Watch Conflicts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Mark Reviewed") {
                        model.run { try store.perform(tournamentID) { (t, c) throws(TournamentError) in t.acknowledgeAllConflicts(now: c.now) } }
                        dismiss()
                    }
                }
            }
        }
    }

    private func describe(_ kind: ScoreEvent.Kind, tournament: Tournament, match: Match) -> String {
        switch kind {
        case .point(let side): "Point for \(tournament.sideName(match.side(side)))"
        case .undo: "Undo"
        case .setScore(let score): "Score set to \(score.a)–\(score.b)"
        case .setSets(let sets): "Sets entered: " + sets.map { "\($0.a)-\($0.b)" }.joined(separator: " ")
        case .finish: "Finish match"
        case .reopen: "Reopen match"
        }
    }
}
