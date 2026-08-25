import Foundation

/// Convenience queries over a franchise chain.
public enum FranchiseNavigator {
    /// The entry that follows `malID` in reading order, if any.
    public static func next(after malID: Int, in franchise: Franchise) -> FranchiseEntry? {
        guard let index = franchise.entries.firstIndex(where: { $0.malId == malID }),
              index + 1 < franchise.entries.count else { return nil }
        return franchise.entries[index + 1]
    }

    /// The entry that precedes `malID`, if any.
    public static func previous(before malID: Int, in franchise: Franchise) -> FranchiseEntry? {
        guard let index = franchise.entries.firstIndex(where: { $0.malId == malID }), index > 0 else { return nil }
        return franchise.entries[index - 1]
    }

    /// Whether the chain has more than the requested entry to show.
    public static func hasChain(_ franchise: Franchise?) -> Bool {
        (franchise?.entries.count ?? 0) > 1
    }
}
