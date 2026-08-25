// FileOps.swift
// FileManager effects behind the FileActing port. One shared do/catch; every
// decision about WHAT to do happened in the covered core.
// Excluded from coverage; audited by scripts/shim-audit.py.

import Foundation

/// Real filesystem effects. Trash (never delete) is the only removal a rule can
/// plan; `remove` exists solely for the explicit `replace` conflict policy.
final class FileOps: FileActing {

    private let manager = FileManager.default

    /// Run one throwing effect, mapping any error to a FileOpError.
    private func attempt(_ body: () throws -> String) -> Result<String, FileOpError> {
        do {
            return .success(try body())
        } catch {
            return .failure(FileOpError(message: error.localizedDescription))
        }
    }

    func ensureDirectory(_ directory: String) -> Result<String, FileOpError> {
        attempt {
            try manager.createDirectory(atPath: directory, withIntermediateDirectories: true)
            return directory
        }
    }

    func move(_ source: String, to destination: String) -> Result<String, FileOpError> {
        attempt {
            try manager.moveItem(atPath: source, toPath: destination)
            return destination
        }
    }

    func copy(_ source: String, to destination: String) -> Result<String, FileOpError> {
        attempt {
            try manager.copyItem(atPath: source, toPath: destination)
            return destination
        }
    }

    func remove(_ path: String) -> Result<String, FileOpError> {
        attempt {
            try manager.removeItem(atPath: path)
            return path
        }
    }

    func trash(_ path: String) -> Result<String, FileOpError> {
        attempt {
            var trashed: NSURL?
            try manager.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: &trashed)
            return trashed?.path ?? path
        }
    }
}
