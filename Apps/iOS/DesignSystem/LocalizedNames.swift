import Foundation
import PadelStore

extension TournamentDraftModel.ScoringMode {
    var localizedName: String {
        switch self {
        case .points: String(localized: "Points")
        case .timed: String(localized: "Timed")
        case .sets: String(localized: "Games & sets")
        }
    }
}
