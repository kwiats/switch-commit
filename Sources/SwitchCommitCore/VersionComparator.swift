import Foundation

public enum VersionComparator {
    /// Returns true when `lhs` is strictly newer than `rhs` using dotted numeric segments.
    /// Non-numeric suffixes (e.g. `-dev`) compare as equal on the numeric prefix then lose to pure releases.
    public static func isNewer(_ lhs: String, than rhs: String) -> Bool {
        compare(lhs, rhs) == .orderedDescending
    }

    public static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = components(lhs)
        let right = components(rhs)
        let count = max(left.count, right.count)
        for index in 0..<count {
            let l = index < left.count ? left[index] : 0
            let r = index < right.count ? right[index] : 0
            if l != r {
                return l > r ? .orderedDescending : .orderedAscending
            }
        }
        let leftSuffix = suffix(lhs)
        let rightSuffix = suffix(rhs)
        if leftSuffix.isEmpty != rightSuffix.isEmpty {
            return leftSuffix.isEmpty ? .orderedDescending : .orderedAscending
        }
        return leftSuffix.compare(rightSuffix)
    }

    private static func components(_ version: String) -> [Int] {
        let core = version.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? version
        return core.split(separator: ".").map { segment in
            Int(segment.filter(\.isNumber)) ?? 0
        }
    }

    private static func suffix(_ version: String) -> String {
        guard let index = version.firstIndex(of: "-") else {
            return ""
        }
        return String(version[version.index(after: index)...])
    }
}
