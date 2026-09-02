import Foundation

enum PreferenceKey {
    static let onboardingVersion = "onboardingVersion"
    static let menuFeedbackEnabled = "menuFeedbackEnabled"
    static let menuFeedbackSeconds = "menuFeedbackSeconds"
    static let turnHistoryEnabled = "turnHistoryEnabled"
    static let highUsageNotificationsEnabled = "highUsageNotificationsEnabled"
    static let promptTitlesEnabled = "promptTitlesEnabled"
    static let readOfficialResetMessageIDs = "readOfficialResetMessageIDs"
}

extension Notification.Name {
    static let bringCodexMeterSettingsToFront = Notification.Name("bringCodexMeterSettingsToFront")
}

extension UserDefaults {
    func value(for key: String, default defaultValue: Bool) -> Bool {
        object(forKey: key) == nil ? defaultValue : bool(forKey: key)
    }

    func value(for key: String, default defaultValue: Double) -> Double {
        object(forKey: key) == nil ? defaultValue : double(forKey: key)
    }
}
