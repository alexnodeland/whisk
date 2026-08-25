// FileFacts.swift
// The immutable metadata snapshot the planner reasons over. Shims build these
// from the real filesystem; the core never touches FileManager.
// In coverage. Imports only Foundation.

import Foundation

/// Everything the rules engine may know about one directory entry.
struct FileFacts: Equatable {
    /// Absolute path of the entry.
    var path: String
    /// The entry's name, including any extension.
    var name: String
    /// Whether the entry is a directory.
    var isDirectory: Bool
    /// Size in bytes (0 for directories).
    var size: UInt64
    /// Creation date.
    var created: Date
    /// Last-modification date.
    var modified: Date
    /// Date the entry was added to its parent folder (falls back to `created`
    /// when the filesystem has no added date).
    var added: Date

    /// The lowercase extension without the dot, or "" when there is none.
    var ext: String {
        let suffix = (name as NSString).pathExtension
        return suffix.lowercased()
    }

    /// The name with its extension removed.
    var stem: String {
        (name as NSString).deletingPathExtension
    }

    /// The date selected by `basis`.
    func date(for basis: AgeBasis) -> Date {
        switch basis {
        case .created: return created
        case .modified: return modified
        case .added: return added
        }
    }
}
