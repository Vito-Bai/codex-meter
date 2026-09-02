import Foundation

@main
enum AppServerClientSmoke {
    static func main() async throws {
        let legacyMessage = try JSONDecoder().decode(
            WorkspaceMessage.self,
            from: Data(#"{"messageID":"legacy","messageBody":"Codex reset","createdAt":null,"archivedAt":null}"#.utf8)
        )
        precondition(legacyMessage.announcedResetAt == nil)

        let rateOnly = try CodexAppServerClient.parse(
            rateResult: [
                "rateLimits": [
                    "primary": ["usedPercent": 23, "windowDurationMins": 300],
                    "credits": ["hasCredits": false, "unlimited": false, "balance": "0"],
                    "planType": "plus"
                ]
            ],
            usageResult: nil,
            messagesResult: [
                "featureEnabled": true,
                "messages": [[
                    "messageId": "reset-1",
                    "messageType": "headline",
                    "messageBody": "Codex usage limits will reset on Sep 3, 2026 at 8:00 PM PT.",
                    "createdAt": 1_781_395_200,
                    "archivedAt": NSNull()
                ]]
            ]
        )
        precondition(rateOnly.quota.primary?.remainingPercent == 77)
        precondition(rateOnly.quota.shortWindow?.remainingPercent == 77)
        precondition(rateOnly.quota.weeklyWindow == nil)
        precondition(rateOnly.usage == nil && rateOnly.dailyUsage == nil)
        precondition(rateOnly.workspaceMessages?.first?.isCodexUsageResetNotice == true)
        precondition(rateOnly.workspaceMessages?.first?.announcedResetAt != nil)

        let dualWindow = try CodexAppServerClient.parse(
            rateResult: [
                "rateLimits": [
                    "primary": ["usedPercent": 10, "windowDurationMins": 300],
                    "secondary": ["usedPercent": 5, "windowDurationMins": 10_080]
                ]
            ],
            usageResult: nil
        )
        precondition(dualWindow.quota.shortWindow?.remainingPercent == 90)
        precondition(dualWindow.quota.weeklyWindow?.remainingPercent == 95)
        precondition(dualWindow.quota.preferredWindow?.remainingPercent == 95)

        let snapshot = try await CodexAppServerClient().fetchSnapshot()
        guard let primary = snapshot.quota.primary else {
            fatalError("Missing primary quota window")
        }
        precondition((0...100).contains(primary.usedPercent))
        let weekly = snapshot.quota.weeklyWindow?.remainingPercent
        let short = snapshot.quota.shortWindow?.remainingPercent
        print("App Server smoke test passed: weekly \(weekly.map(String.init) ?? "—")%, 5h \(short.map(String.init) ?? "—")%, \(snapshot.dailyUsage?.count ?? 0) daily buckets")
    }
}
