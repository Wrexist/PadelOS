import SwiftUI
import PadelCore
import PadelStore

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(SettingsStore.self) private var settings
    @State private var showingIntroduction = false
    @State private var expandedFormat: TournamentFormat?

    var body: some View {
        Form {
            Section {
                header
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }

            Section {
                Picker(selection: binding(\.defaultFormat)) {
                    ForEach(TournamentFormat.allCases) { Text(verbatim: $0.localizedName).tag($0) }
                } label: {
                    Label("Default format", systemImage: "square.grid.2x2.fill")
                        .labelStyle(SettingsIconLabelStyle(tint: Theme.Colors.accent))
                }
                Stepper(value: binding(\.defaultCourtCount), in: 1...ConfigurationValidator.maximumCourts) {
                    Label {
                        Text("Courts: \(settings.settings.defaultCourtCount)")
                            .contentTransition(.numericText(value: Double(settings.settings.defaultCourtCount)))
                            .animation(Motion.snappy, value: settings.settings.defaultCourtCount)
                    } icon: {
                        Image(systemName: "square.split.2x1.fill")
                    }
                    .labelStyle(SettingsIconLabelStyle(tint: Theme.Colors.accent))
                }
                Picker(selection: binding(\.defaultPoints)) {
                    ForEach(TournamentDraftModel.pointOptions, id: \.self) { Text("\($0) points").tag($0) }
                } label: {
                    Label("Points per match", systemImage: "trophy.fill")
                        .labelStyle(SettingsIconLabelStyle(tint: Theme.Colors.accent))
                }
                if !settings.settings.recentPlayerNames.isEmpty {
                    Button(role: .destructive) {
                        settings.update { $0.recentPlayerNames = [] }
                    } label: {
                        Label("Forget Recent Player Names", systemImage: "person.crop.circle.badge.xmark")
                    }
                    .labelStyle(SettingsIconLabelStyle(tint: Theme.Colors.danger, symbolColor: .white))
                }
            } header: {
                Text("New tournaments")
            }
            .labelStyle(SettingsIconLabelStyle(tint: Theme.Colors.accent))
            .listRowBackground(Theme.Colors.surface)

            Section {
                Toggle(isOn: binding(\.hapticsEnabled)) {
                    Label("Haptic feedback", systemImage: "hand.tap.fill")
                        .labelStyle(SettingsIconLabelStyle(tint: Color(hex: 0x8FD3FE)))
                }
                Toggle(isOn: binding(\.keepScreenAwakeWhileScoring)) {
                    Label("Keep screen awake while scoring", systemImage: "sun.max.fill")
                        .labelStyle(SettingsIconLabelStyle(tint: Color(hex: 0x8FD3FE)))
                }
                Toggle(isOn: binding(\.liveActivitiesEnabled)) {
                    Label("Live Activity on Lock Screen", systemImage: "platter.filled.top.iphone")
                        .labelStyle(SettingsIconLabelStyle(tint: Color(hex: 0x8FD3FE)))
                }
                .accessibilityHint("Shows the score on the Lock Screen and Dynamic Island with +1 buttons")
            } header: {
                Text("Scoring")
            }
            .labelStyle(SettingsIconLabelStyle(tint: Color(hex: 0x8FD3FE)))
            .tint(Theme.Colors.accent)
            .listRowBackground(Theme.Colors.surface)

            Section {
                HStack(spacing: Theme.Spacing.m) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Theme.Colors.surfaceRaised)
                        Image(systemName: "applewatch")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.Colors.textPrimary)
                    }
                    .frame(width: 30, height: 30)
                    .accessibilityHidden(true)
                    Text(verbatim: watchStatusText)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    watchStatusDot
                }
                if !settings.settings.unroutableEvents.isEmpty {
                    Text("\(settings.settings.unroutableEvents.count) score changes from Apple Watch belonged to deleted tournaments and were set aside.")
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
                    Button {
                        withAnimation(Motion.smooth.motionSafe) {
                            expandedFormat = expandedFormat == format ? nil : format
                        }
                    } label: {
                        HStack(alignment: .top, spacing: Theme.Spacing.m) {
                            FormatGlyph(format: format, isSelected: expandedFormat == format, size: CGSize(width: 46, height: 32))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(verbatim: format.localizedName)
                                    .font(.padelName.weight(.semibold))
                                    .foregroundStyle(Theme.Colors.textPrimary)
                                Text(verbatim: expandedFormat == format ? rulesText(format) : format.localizedSummary)
                                    .font(.padelMeta)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .contentTransition(.opacity)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.down")
                                .font(.footnote.weight(.bold))
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .rotationEffect(.degrees(expandedFormat == format ? 180 : 0))
                                .accessibilityHidden(true)
                        }
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                }
            } header: {
                Text("How the formats work")
            }
            .listRowBackground(Theme.Colors.surface)

            Section {
                Button {
                    showingIntroduction = true
                } label: {
                    Label("Show introduction", systemImage: "sparkles")
                        .foregroundStyle(Theme.Colors.textPrimary)
                }
                .labelStyle(SettingsIconLabelStyle(tint: Theme.Colors.accent))
                .accessibilityIdentifier("showIntroductionButton")
                Text("Works fully offline. No account, no tracking. Tournaments are stored only on this iPhone.")
                    .font(.padelMeta)
                    .foregroundStyle(Theme.Colors.textSecondary)
            } header: {
                Text("About")
            }
            .listRowBackground(Theme.Colors.surface)
        }
        .scrollContentBackground(.hidden)
        .screenBackground()
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showingIntroduction) {
            OnboardingView { showingIntroduction = false }
        }
    }

    /// Brand, version and the three promises, as a scoreboard-style card.
    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack {
                BrandMark(animated: true)
                Spacer()
                Text(verbatim: version)
                    .font(.padelEyebrow)
                    .foregroundStyle(Theme.Colors.onDarkSecondary)
                    .padding(.horizontal, Theme.Spacing.s)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.08), in: Capsule())
                    .accessibilityLabel(Text("Version"))
                    .accessibilityValue(Text(verbatim: version))
            }
            HStack(spacing: Theme.Spacing.s) {
                promise("Works offline", symbol: "wifi.slash")
                promise("No account needed", symbol: "person.crop.circle.badge.xmark")
                promise("Data stays on your devices", symbol: "lock.shield.fill")
            }
        }
        .padding(Theme.Spacing.l)
        .background {
            ZStack {
                Theme.Colors.graphite
                RadialGradient(colors: [Theme.Colors.accent.opacity(0.25), .clear], center: .topTrailing, startRadius: 4, endRadius: 260)
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .environment(\.colorScheme, .dark)
        .padding(.vertical, Theme.Spacing.s)
    }

    private func promise(_ title: LocalizedStringKey, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol)
                .font(.callout.weight(.bold))
                .foregroundStyle(Theme.Colors.accent)
                .accessibilityHidden(true)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.s)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    @ViewBuilder
    private var watchStatusDot: some View {
        switch model.watchStatus {
        case .reachable: LiveDot(size: 9)
        case .notReachable: Circle().fill(Theme.Colors.warning).frame(width: 9, height: 9).accessibilityHidden(true)
        case .notInstalled, .notSupported: EmptyView()
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(get: { settings.settings[keyPath: keyPath] }, set: { value in settings.update { $0[keyPath: keyPath] = value } })
    }

    private var watchStatusText: String {
        switch model.watchStatus {
        case .notSupported: String(localized: "Apple Watch is not available on this device.")
        case .notInstalled: String(localized: "Install PadelOS on your Apple Watch from the Watch app.")
        case .reachable: String(localized: "Connected")
        case .notReachable: String(localized: "Paired · not reachable right now")
        }
    }

    private func rulesText(_ format: TournamentFormat) -> String {
        switch format {
        case .americano:
            String(localized: "Partners rotate every round. Both players on a team receive the team's points. Ranked by total points, then wins, then point difference.")
        case .mexicano:
            String(localized: "Round 1 is drawn, then each round groups players by the standings: 1st & 4th play 2nd & 3rd, avoiding repeat partners where possible.")
        case .mixedAmericano:
            String(localized: "Like Americano, but every team has one player from each of your two groups.")
        case .mixicano:
            String(localized: "Mexicano with your two groups: each court gets the next two players of each group, and every team has one of each.")
        case .teamAmericano:
            String(localized: "Fixed teams play a round robin. Teams are ranked by total points, wins, head-to-head, then point difference.")
        case .teamMexicano:
            String(localized: "Fixed teams; after round 1 the 1st team plays the 2nd, the 3rd plays the 4th, avoiding repeat meetings where possible.")
        case .swiss:
            String(localized: "Fixed teams. Each round, teams with the same number of wins play each other, and no two teams meet twice. Ranked by wins, then total points.")
        case .kingOfTheCourt:
            String(localized: "After each round winners move up one court and losers move down; partners split up. Court 1 is the king's court.")
        }
    }
}

/// iOS-Settings-style row icon: a white symbol on a rounded, tinted square.
struct SettingsIconLabelStyle: LabelStyle {
    var tint: Color
    var symbolColor: Color = Theme.Colors.ink

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Theme.Spacing.m) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(tint)
                configuration.icon
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(symbolColor)
            }
            .frame(width: 30, height: 30)
            .accessibilityHidden(true)
            configuration.title
        }
    }
}
