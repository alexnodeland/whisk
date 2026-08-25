// UpdateFetcher.swift
// URLSession behind the UpdateFetching port: one small JSON GET and one file
// download. Both trust TLS to github.com and nothing else (ADR 0012); what to
// do with the bytes is decided in the covered core.
// Excluded from coverage; audited by scripts/shim-audit.py.

import Foundation

/// Real HTTPS fetching.
final class UpdateFetcher: UpdateFetching {

    func fetch(url: String, completion: @escaping (Data?) -> Void) {
        URLSession.shared.dataTask(with: URL(string: url)!) { data, _, _ in
            DispatchQueue.main.async { completion(data) }
        }.resume()
    }

    func download(url: String, completion: @escaping (String?) -> Void) {
        URLSession.shared.downloadTask(with: URL(string: url)!) { temporary, _, _ in
            // The temporary file dies with this closure, so claim it first.
            let destination = NSTemporaryDirectory() + "whisk-update-\(ProcessInfo.processInfo.globallyUniqueString).zip"
            let moved: Void? = temporary.flatMap { try? FileManager.default.moveItem(atPath: $0.path, toPath: destination) }
            DispatchQueue.main.async { completion(moved == nil ? nil : destination) }
        }.resume()
    }
}
