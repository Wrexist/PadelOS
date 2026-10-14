import SwiftUI
import PadelCore
import PadelStore

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        Form {
            Section("New tournaments") {
                Picker("Default format", selection: binding(\.defaultFormat)) {
                    ForEach(TournamentFormat.allCases) { Text($0.displayName).tag($0) }
                }
                Stepper("Courts: \(settings.settings.defaultCourtCount)", value: binding(\.defaultCourtCount), in: 1...ConfigurationValidator.maximumCourts)
                Picker("Points per match", selection: binding(\.defaultPoints)) {
                    ForEach(TournamentDraftModel.pointOptions, id: \.self) { Text("\($0) points").tag($0) }
                }
                if !settings.settings.recentPlayerNames.isEmpty {
                    Button("Forget Recent Player Names", role: .destructive) {
                        settings.update { $0.recentPlayerNames = [] }
                    }
                }
            }
            .listRowBackground(Theme.Colors.surface)

            Section("Scoring") {
                Toggle("Haptic feedback", isOn: binding(\.hapticsEnabled))
                Toggle("Keep screen awake while scoring", isOn: binding(\.keepScreenAwakeWhileScoring))
                Toggle("Live Activity on Lock Screen", isOn: binding(\.liveActivitiesEnabled))
                    .accessibilityHint("Shows the score on the Lock Screen and Dynamic Island with +1 buttons")
            }
            .listRowBackground(Theme.Colors.surface)

            Section {
                HStack {
                    Image(systemName: "applewatch")
                        .foregroundStyle(Theme.Colors.accentText)
                        .accessibilityHidden(true)
                    Text(watchStatusText)
                    Spacer()
                }
                if !settings.settings.unroutableEvents.isEmpty {
                    Text("\(settings.settings.unroutableEvents.count) score change\(settings.settings.unroutableEvents.count == 1 ? "" : "s") from Apple Watch belonged to deleted tournaments and were set aside.")
                        .font(.padelMeta)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Button("Clear") { settings.update { $0.unroutableEvents = [] } }
                }
                if let error = model.sync.lastError {
                    Text("Last sync problem: \(error)")
                        .font(.padelMeta)
                        .foregroundStyle(Theme.Colors.warning)
                }
            } header: {
                Text("Apple Watch")
            } footer: {
                Text("Score on the watch even without your iPhone nearby. Points are stored on the watch and sent when the devices reconnect.")
            }
            .listRowBackground(Theme.Colors.surface)

            Section {
                ForEach(TournamentFormat.allCases) { format in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(format.displayName).font(.padelName)
                        Text(rulesText(format)).font(.padelMeta).foregroundStyle(Theme.Colors.textSecondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            } header: {
                Text("How the formats work")
            }
            .listRowBackground(Theme.Colors.surface)

            Section("About") {
                ValueRow(symbol: "info.circle", title: "Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                Text("Works fully offline. No account, no tracking. Tournaments are stored only on this iPhone.")
                    .font(.padelMeta)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .listRowBackground(Theme.Colors.surface)
        }
        .scrollContentBackground(.hidden)
        .screenBackground()
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(get: { settings.settings[keyPath: keyPath] }, set: { value in settings.update { $0[keyPath: keyPath] = value } })
    }

    private var watchStatusText: String {
        switch model.watchStatus {
        case .notSupported: "Apple Watch is not available on this device."
        case .notInstalled: "Install PadelOS on your Apple Watch from the Watch app."
        case .reachable: "Connected"
        case .notReachable: "Paired · not reachable right now"
        }
    }

    private func rulesText(_ format: TournamentFormat) -> String {
        switch format {
        case .americano:
            "Partners rotate every round. Both players on a team receive the team's points. Ranked by total points, then wins, then point difference."
        case .mexicano:
            "Round 1 is drawn, then each round groups players by the standings: 1st & 4th play 2nd & 3rd, avoiding repeat partners where possible."
        case .mixedAmericano:
            "Like Americano, but every team has one player from each of your two groups."
        case .mixicano:
            "Mexicano with your two groups: each court gets the next two players of each group, and every team has one of each."
        case .teamAmericano:
            "Fixed teams play a round robin. Teams are ranked by total points, wins, head-to-head, then point difference."
        case .teamMexicano:
            "Fixed teams; after round 1 the 1st team plays the 2nd, the 3rd plays the 4th, avoiding repeat meetings where possible."
        case .kingOfTheCourt:
            "After each round winners move up one court and losers move down; partners split up. Court 1 is the king's court."
        }
    }
}
