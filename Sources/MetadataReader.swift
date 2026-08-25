// MetadataReader.swift
// FileManager-backed DirectoryEnumerating shim: reads entry names and resource
// values; the defaulting decisions live in FileFacts.fromResource (covered).
// Excluded from coverage; audited by scripts/shim-audit.py.

import Foundation

/// Real directory snapshots.
final class MetadataReader: DirectoryEnumerating {

    private static let keys: [URLResourceKey] = [
        .isDirectoryKey, .fileSizeKey, .creationDateKey, .contentModificationDateKey, .addedToDirectoryDateKey,
    ]

    func facts(inDirectory directory: String) -> [FileFacts]? {
        let url = URL(fileURLWithPath: directory)
        guard
            let entries = try? FileManager.default.contentsOfDirectory(
                at: url, includingPropertiesForKeys: Self.keys, options: [.skipsHiddenFiles])
        else { return nil }
        return entries.map { entry in
            let values = try? entry.resourceValues(forKeys: Set(Self.keys))
            return FileFacts.fromResource(
                path: entry.path, name: entry.lastPathComponent,
                isDirectory: values?.isDirectory, size: values?.fileSize,
                created: values?.creationDate, modified: values?.contentModificationDate,
                added: values?.addedToDirectoryDate)
        }
    }

    func names(inDirectory directory: String) -> [String]? {
        try? FileManager.default.contentsOfDirectory(atPath: directory)
    }
}
