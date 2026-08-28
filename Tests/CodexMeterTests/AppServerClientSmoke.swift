import Foundation

@main
enum AppServerClientSmoke {
    static func main() async throws {
        let rateOnly = try CodexAppServerClient.parse(
            rateResult: [
                "rateLimits": [
                    "primary": ["usedPercent": 23, "windowDurationMins": 300],
                    "credits": ["hasCredits": false, "unlimited": false, "balance": "0"],
                    "planType": "plus"
                ]
            ],
            usageResult: nil
        )
        precondition(rateOnly.quota.primary?.remainingPercent == 77)
        precondition(rateOnly.usage == nil && rateOnly.dailyUsage == nil)

        let snapshot = try await CodexAppServerClient().fetchSnapshot()
        guard let primary = snapshot.quota.primary else {
            fatalError("Missing primary quota window")
        }
        precondition((0...100).contains(primary.usedPercent))
        print("App Server smoke test passed: \(primary.remainingPercent)% remaining, \(snapshot.dailyUsage?.count ?? 0) daily buckets")
    }
}
