import Foundation

/// Tokens from one or more model calls.
public struct TokenCounts: Codable, Hashable, Sendable {
    public var input: Int = 0
    public var output: Int = 0
    public var cacheWrite: Int = 0
    public var cacheRead: Int = 0

    public init(input: Int = 0, output: Int = 0, cacheWrite: Int = 0, cacheRead: Int = 0) {
        self.input = input
        self.output = output
        self.cacheWrite = cacheWrite
        self.cacheRead = cacheRead
    }

    public var total: Int { input + output + cacheWrite + cacheRead }

    public static func + (a: TokenCounts, b: TokenCounts) -> TokenCounts {
        TokenCounts(input: a.input + b.input, output: a.output + b.output,
                    cacheWrite: a.cacheWrite + b.cacheWrite, cacheRead: a.cacheRead + b.cacheRead)
    }

    public static func += (a: inout TokenCounts, b: TokenCounts) { a = a + b }
}

/// How much of the weekly Max limit a call uses, in "units".
///
/// Anthropic doesn't publish the limit in tokens, so Zenith weighs tokens the way the
/// limit does in practice: by model (Opus spends it fastest) and by kind (output costs
/// most, cache reads almost nothing). A unit is roughly a dollar of API-equivalent work.
/// The Budget page turns units into a share of the week with a calibration the user
/// sets from Claude's own usage page.
public enum UsageMath {
    /// Per million input tokens, relative across the three models.
    public static func rate(_ tier: ModelTier) -> Double {
        switch tier {
        case .haiku: return 1
        case .sonnet: return 3
        case .opus: return 5
        }
    }

    public static func units(_ c: TokenCounts, _ tier: ModelTier) -> Double {
        let weighted = Double(c.input) + Double(c.cacheWrite) * 1.25 + Double(c.cacheRead) * 0.1 + Double(c.output) * 5
        return weighted * rate(tier) / 1_000_000
    }
}

/// A mission's usage so far, by model.
public struct UsageLedger: Codable, Hashable, Sendable {
    public var byModel: [String: TokenCounts] = [:]

    public init() {}

    public mutating func add(_ counts: TokenCounts, _ tier: ModelTier) {
        byModel[tier.rawValue, default: TokenCounts()] += counts
    }

    public mutating func add(_ other: UsageLedger) {
        for (key, counts) in other.byModel { byModel[key, default: TokenCounts()] += counts }
    }

    public func counts(_ tier: ModelTier) -> TokenCounts { byModel[tier.rawValue] ?? TokenCounts() }

    public var units: Double {
        byModel.reduce(0) { sum, entry in
            sum + UsageMath.units(entry.value, ModelTier(rawValue: entry.key) ?? .sonnet)
        }
    }

    public var tokens: Int { byModel.values.reduce(0) { $0 + $1.total } }
}
