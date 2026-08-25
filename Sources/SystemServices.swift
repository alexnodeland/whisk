// SystemServices.swift
// Zero-branch shims for the wall clock and UserDefaults. Excluded from
// coverage; audited by scripts/shim-audit.py.

import Foundation

/// The real wall clock.
final class SystemClock: Clock {
    func now() -> Date { Date() }
}

/// UserDefaults behind the KeyValueStore port. WHISK_DEFAULTS_SUITE reroutes
/// persistence to a throwaway suite so integration runs never touch real state.
final class DefaultsStore: KeyValueStore {
    private let defaults =
        ProcessInfo.processInfo.environment["WHISK_DEFAULTS_SUITE"]
        .flatMap(UserDefaults.init(suiteName:)) ?? .standard

    func string(forKey key: String) -> String? {
        defaults.string(forKey: key)
    }

    func set(_ value: String?, forKey key: String) {
        defaults.set(value, forKey: key)
    }
}
