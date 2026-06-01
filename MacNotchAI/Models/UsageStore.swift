import SwiftUI
import Combine

/// Decoded usage block returned by the proxy (`/v1/complete` and `/v1/usage`).
/// The daily quota is a TOKEN budget (actual Gemini tokens billed, input + output —
/// so images count too); the trial is still interaction-based.
struct HostedUsage: Decodable {
    let tier: String
    let inTrial: Bool
    let trialRemaining: Int        // interactions left in the one-time trial
    let dailyTokenBudget: Int      // today's total token budget
    let dailyTokensRemaining: Int  // tokens left today
    let resetAt: String?
}

/// Client-side mirror of the hosted free-tier usage. The server is the source of
/// truth; this exists so the menu can show "X of N free left" instantly without a
/// round-trip. Updated from every `/v1/complete` response and `refresh()`.
@MainActor
final class UsageStore: ObservableObject {
    static let shared = UsageStore()

    private static let keyTrialRemaining = "usage.trialRemaining"
    private static let keyTokenBudget    = "usage.dailyTokenBudget"
    private static let keyTokensRemaining = "usage.dailyTokensRemaining"
    private static let keyInTrial        = "usage.inTrial"

    /// Interactions remaining in the one-time trial (meaningful while `inTrial`).
    @Published var trialRemaining: Int?
    /// Today's total daily token budget.
    @Published var dailyTokenBudget: Int?
    /// Tokens left in today's budget.
    @Published var dailyTokensRemaining: Int?
    /// True while the device is still inside its one-time trial allowance.
    @Published var inTrial: Bool = true
    /// Next reset (ISO-8601, UTC) for the daily budget.
    @Published var resetAt: String?

    private init() {
        let d = UserDefaults.standard
        if d.object(forKey: Self.keyTrialRemaining) != nil {
            trialRemaining = d.integer(forKey: Self.keyTrialRemaining)
        }
        if d.object(forKey: Self.keyTokenBudget) != nil {
            dailyTokenBudget = d.integer(forKey: Self.keyTokenBudget)
        }
        if d.object(forKey: Self.keyTokensRemaining) != nil {
            dailyTokensRemaining = d.integer(forKey: Self.keyTokensRemaining)
        }
        inTrial = d.object(forKey: Self.keyInTrial) as? Bool ?? true
    }

    /// Apply a fresh usage snapshot from the proxy and persist the mirror.
    func apply(_ usage: HostedUsage) {
        trialRemaining       = usage.trialRemaining
        dailyTokenBudget     = usage.dailyTokenBudget
        dailyTokensRemaining = usage.dailyTokensRemaining
        inTrial              = usage.inTrial
        resetAt              = usage.resetAt
        let d = UserDefaults.standard
        d.set(usage.trialRemaining,       forKey: Self.keyTrialRemaining)
        d.set(usage.dailyTokenBudget,     forKey: Self.keyTokenBudget)
        d.set(usage.dailyTokensRemaining, forKey: Self.keyTokensRemaining)
        d.set(usage.inTrial,              forKey: Self.keyInTrial)
    }

    /// Short label for the menu bar. The trial counts interactions ("8 free left");
    /// the daily quota is a token budget, shown as a percentage ("73% free today")
    /// since raw token counts are meaningless to the user.
    var menuLabel: String? {
        if inTrial {
            guard let trialRemaining else { return nil }
            return "\(trialRemaining) free left"
        }
        guard let dailyTokensRemaining, let dailyTokenBudget, dailyTokenBudget > 0 else { return nil }
        let pct = max(0, min(100, Int((Double(dailyTokensRemaining) / Double(dailyTokenBudget) * 100).rounded())))
        return "\(pct)% free today"
    }

    /// Fetch current usage without consuming quota. No-op until the backend is live.
    func refresh() async {
        guard let base = BackendConfig.proxyBaseURL else { return }
        var req = URLRequest(url: base.appendingPathComponent("v1/usage"))
        req.setValue(DeviceIdentity.current, forHTTPHeaderField: "X-Device-Id")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let decoded = try? JSONDecoder().decode(UsageOnly.self, from: data),
              let usage = decoded.usage else { return }
        apply(usage)
    }

    private struct UsageOnly: Decodable { let usage: HostedUsage? }
}
