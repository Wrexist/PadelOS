import SwiftUI
import PadelCore
import PadelStore

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(TournamentStore.self) private var store
    @Binding var path: [Route]
    @State private var creation: CreationRequest?

    /// Which flavour of the creation flow to open.
    struct CreationRequest: Identifiable {
        let id = UUID()
        var quickAmericano: Bool
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                header
                if !store.loadIssues.isEmpty {
                    MessageBanner(style: .warning, message: store.loadIssues.joined(separator: "\n"), onDismiss: { store.dismissLoadIssues() })
                }
                if let message = model.errorMessage {
                    MessageBanner(style: .error, message: message, onDismiss: { model.errorMessage = nil })
                }
                actions
                quickStart
                recent
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.bottom, Theme.Spacing.xxl)
        }
        .screenBackground()
        .toolbar(.hidden, for: .navigationBar)
        .task {
            // Screenshot run only (`-demoScreen create`).
            if AppModel.demoScreen == "create" && creation == nil {
                try? await Task.sleep(for: .milliseconds(300))
                creation = CreationRequest(quickAmericano: false)
            }
        }
        .fullScreenCover(item: $creation) { request in
            CreateTournamentFlow(quickAmericano: request.quickAmericano) { created in
                creation = nil
                path = [.tournament(created.id)]
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            HStack {
                BrandMark()
                Spacer()
                Button {
                    path.append(.settings)
                } label: {
                    Image(systemName: "gearshape")
                        .font(.title3)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .frame(width: Theme.minimumTapTarget, height: Theme.minimumTapTarget)
                }
                .accessibilityLabel("Settings")
                .accessibilityIdentifier("settingsButton")
            }
            Text("Play together.\nKeep score.")
                .font(.padelHero)
                .foregroundStyle(Theme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        }
        .padding(.top, Theme.Spacing.l)
    }

    private var actions: some View {
        VStack(spacing: Theme.Spacing.m) {
            Button {
                creation = CreationRequest(quickAmericano: false)
            } label: {
                Label("Create Tournament", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.padelPrimary)
            .accessibilityIdentifier("createTournamentButton")

            if let active = store.resumableTournament {
                Button {
                    path = [.tournament(active.id)]
                } label: {
                    HStack {
                        Image(systemName: "play.circle")
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Resume \(active.name)")
                                .lineLimit(1)
                            Text(active.progressLabel)
                                .font(.padelMeta)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
                .buttonStyle(.padelSecondary)
                .accessibilityIdentifier("resumeButton")
            }
        }
    }

    private var quickStart: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            SectionHeader(title: "Quick start")
            Button {
                creation = CreationRequest(quickAmericano: true)
            } label: {
                HStack(spacing: Theme.Spacing.m) {
                    Image(systemName: "bolt.fill")
                        .foregroundStyle(Theme.Colors.onAccent)
                        .frame(width: 36, height: 36)
                        .background(Theme.Colors.accent, in: Circle())
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Americano")
                            .font(.padelName)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Text(quickStartDetail)
                            .font(.padelMeta)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .cardStyle(padding: Theme.Spacing.m)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Starts a new Americano with your usual settings")
            .accessibilityIdentifier("quickStartButton")
        }
    }

    private var quickStartDetail: String {
        let settings = model.settings.settings
        let recent = settings.recentPlayerNames.count
        let players = recent >= 4 ? String(localized: "\(min(recent, settings.defaultCourtCount * 4)) recent players") : String(localized: "Add players")
        return "\(players) · \(settings.defaultCourtCount) courts · \(settings.defaultPoints) points"
    }

    @ViewBuilder
    private var recent: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            SectionHeader(title: "Recent tournaments")
            if store.recentTournaments.isEmpty {
                EmptyStateView(symbol: "sportscourt", title: "No tournaments yet", message: "Create one in under a minute. No account needed — everything stays on this iPhone.")
                    .cardStyle()
            } else {
                VStack(spacing: 0) {
                    ForEach(store.recentTournaments) { tournament in
                        Button {
                            path = [.tournament(tournament.id)]
                        } label: {
                            TournamentRow(tournament: tournament)
                        }
                        .buttonStyle(.plain)
                        if tournament.id != store.recentTournaments.last?.id {
                            Divider().overlay(Theme.Colors.separator).padding(.leading, Theme.Spacing.l)
                        }
                    }
                }
                .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
            }
        }
    }
}

struct TournamentRow: View {
    let tournament: Tournament

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(tournament.name)
                    .font(.padelName)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
                Text(tournament.summaryLine)
                    .font(.padelMeta)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(tournament.status == .completed ? "Finished" : tournament.shortProgressLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tournament.status == .completed ? Theme.Colors.textSecondary : Theme.Colors.accentText)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.Colors.textSecondary)
                .accessibilityHidden(true)
        }
        .padding(Theme.Spacing.l)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the tournament")
    }
}

/// The two-stroke "court lines" mark used as the brand logo.
struct BrandMark: View {
    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            HStack(spacing: 3) {
                ForEach(0..<2, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Theme.Colors.accent)
                        .frame(width: 5, height: 20)
                        .rotationEffect(.degrees(20))
                }
            }
            Text("PADEL")
                .font(.system(.title3, design: .default).weight(.heavy))
                .tracking(1)
                .foregroundStyle(Theme.Colors.textPrimary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("PadelOS")
    }
}
