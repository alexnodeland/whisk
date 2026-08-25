// UpdatePlanner.swift
// Pure update policy: what "newer" means, when a check is due, and how the
// GitHub latest-release payload maps to a downloadable build. All decisions
// here; the network lives behind the UpdateFetching port.
// In coverage. Imports only Foundation.

import Foundation

/// A published build the app could update to.
struct ReleaseInfo: Equatable {
    /// The version, without any leading "v".
    var version: String
    /// The download URL of the stable-named universal zip.
    var zipURL: String
}

/// Pure decisions for the self-updater (ADR 0012).
enum UpdatePlanner {

    /// Where the latest release is described.
    static let latestReleaseURL = "https://api.github.com/repos/alexnodeland/whisk/releases/latest"

    /// The release asset the updater installs — the same stable name the
    /// Homebrew cask pins, so both channels ship identical bytes.
    static let assetName = "Whisk-universal.zip"

    /// How stale the last check must be before another is due.
    static let checkInterval: TimeInterval = 24 * 3600

    /// The GitHub payload, reduced to what the decision needs.
    private struct LatestRelease: Decodable {
        struct Asset: Decodable {
            let name: String
            let browserDownloadUrl: String

            enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadUrl = "browser_download_url"
            }
        }

        let tagName: String
        let assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case assets
        }
    }

    /// Parse the latest-release payload into a candidate build, or nil when the
    /// payload is malformed or carries no universal zip.
    static func parseLatest(_ data: Data) -> ReleaseInfo? {
        guard let release = try? JSONDecoder().decode(LatestRelease.self, from: data) else { return nil }
        guard let asset = release.assets.first(where: { $0.name == assetName }) else { return nil }
        let version = release.tagName.hasPrefix("v") ? String(release.tagName.dropFirst()) : release.tagName
        return ReleaseInfo(version: version, zipURL: asset.browserDownloadUrl)
    }

    /// Numeric dot-component comparison; missing components count as zero, and
    /// a non-numeric component counts as zero so a malformed remote tag can
    /// never look "newer" than a well-formed local version.
    static func isNewer(_ remote: String, than current: String) -> Bool {
        let remoteParts = remote.split(separator: ".").map { Int($0) ?? 0 }
        let currentParts = current.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(remoteParts.count, currentParts.count) {
            let lhs = index < remoteParts.count ? remoteParts[index] : 0
            let rhs = index < currentParts.count ? currentParts[index] : 0
            if lhs != rhs { return lhs > rhs }
        }
        return false
    }

    /// Whether a background check is due at `now`.
    static func shouldCheck(now: Date, lastCheck: Date?, autoCheck: Bool) -> Bool {
        guard autoCheck else { return false }
        guard let lastCheck else { return true }
        return now.timeIntervalSince(lastCheck) >= checkInterval
    }
}
