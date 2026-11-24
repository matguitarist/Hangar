import Foundation
import HangarKit

extension LaunchRecord.Outcome {
    var title: String {
        switch self {
        case .worked: String(localized: "Worked")
        case .crashed: String(localized: "Crashed")
        case .didntStart: String(localized: "Didn't start")
        case .quitRightAway: String(localized: "Quit right away")
        }
    }
}

extension LaunchRecord {
    /// "Crashed after 4 s · 12 launches"
    func summary(launches: Int) -> String {
        let what = outcome == .crashed && played > 0
            ? String(localized: "Crashed after \(Int(played)) s") : outcome.title
        return String(localized: "\(what) · \(launches) launches")
    }
}
