// Fakes.swift
// In-memory conformances of every port, used by the unit tests. Each fake
// records calls and lets tests script answers; none touches the real system.

import Foundation

@testable import WhiskCore

/// A cancellable that remembers whether it was cancelled.
final class FakeCancellable: Cancellable {
    private(set) var cancelled = false

    func cancel() {
        cancelled = true
    }
}

/// A settable wall clock.
final class FakeClock: Clock {
    var current: Date

    init(_ start: Date = Date(timeIntervalSince1970: 1_000_000)) {
        current = start
    }

    func now() -> Date { current }

    func advance(_ seconds: TimeInterval) {
        current = current.addingTimeInterval(seconds)
    }
}

/// A scheduler that stores blocks for manual firing.
final class FakeScheduler: Scheduler {
    struct Scheduled {
        var seconds: TimeInterval
        var handler: () -> Void
        var handle: FakeCancellable
        var repeating: Bool
    }

    private(set) var scheduled: [Scheduled] = []

    func schedule(after seconds: TimeInterval, _ handler: @escaping () -> Void) -> Cancellable {
        let handle = FakeCancellable()
        scheduled.append(Scheduled(seconds: seconds, handler: handler, handle: handle, repeating: false))
        return handle
    }

    func every(seconds: TimeInterval, _ handler: @escaping () -> Void) -> Cancellable {
        let handle = FakeCancellable()
        scheduled.append(Scheduled(seconds: seconds, handler: handler, handle: handle, repeating: true))
        return handle
    }

    /// Fire every non-cancelled one-shot block scheduled so far (once).
    func fireAllOneShots() {
        let batch = scheduled.filter { !$0.repeating && !$0.handle.cancelled }
        scheduled.removeAll { !$0.repeating }
        for item in batch { item.handler() }
    }

    /// Fire every non-cancelled repeating block once.
    func fireRepeating() {
        for item in scheduled where item.repeating && !item.handle.cancelled {
            item.handler()
        }
    }
}

/// A directory tree of scripted facts. nil marks an unreadable directory.
final class FakeEnumerator: DirectoryEnumerating {
    var tree: [String: [FileFacts]] = [:]
    var denied: Set<String> = []
    /// Directories whose `names` listing (only) is unreadable.
    var namesDenied: Set<String> = []

    func facts(inDirectory directory: String) -> [FileFacts]? {
        if denied.contains(directory) { return nil }
        return tree[directory] ?? []
    }

    func names(inDirectory directory: String) -> [String]? {
        if namesDenied.contains(directory) { return nil }
        return facts(inDirectory: directory)?.map(\.name)
    }
}

/// Records file operations; failures are scripted by path.
final class FakeFileActor: FileActing {
    private(set) var log: [String] = []
    var failing: Set<String> = []

    private func perform(_ verb: String, _ path: String, result: String) -> Result<String, FileOpError> {
        log.append("\(verb) \(path) -> \(result)")
        if failing.contains(path) || failing.contains(result) {
            return .failure(FileOpError(message: "\(verb) failed"))
        }
        return .success(result)
    }

    func ensureDirectory(_ directory: String) -> Result<String, FileOpError> {
        perform("mkdir", directory, result: directory)
    }

    func move(_ source: String, to destination: String) -> Result<String, FileOpError> {
        perform("move", source, result: destination)
    }

    func copy(_ source: String, to destination: String) -> Result<String, FileOpError> {
        perform("copy", source, result: destination)
    }

    func remove(_ path: String) -> Result<String, FileOpError> {
        perform("remove", path, result: path)
    }

    func trash(_ path: String) -> Result<String, FileOpError> {
        perform("trash", path, result: "/trash/" + (path as NSString).lastPathComponent)
    }
}

/// Captures run requests; tests invoke the stored completions.
final class FakeRunner: CommandRunning {
    struct Request {
        var command: String
        var arguments: [String]
        var directory: String
        var environment: [String: String]
        var timeout: TimeInterval
        var completion: (Int32?, String) -> Void
    }

    private(set) var requests: [Request] = []

    func run(
        command: String,
        arguments: [String],
        directory: String,
        environment: [String: String],
        timeout: TimeInterval,
        completion: @escaping (Int32?, String) -> Void
    ) {
        requests.append(
            Request(
                command: command, arguments: arguments, directory: directory,
                environment: environment, timeout: timeout, completion: completion))
    }
}

/// Records posted notifications.
final class FakeNotifier: Notifying {
    private(set) var posted: [(title: String, body: String)] = []

    func post(title: String, body: String) {
        posted.append((title, body))
    }
}

/// An in-memory key-value store.
final class FakeKVStore: KeyValueStore {
    var values: [String: String] = [:]

    func string(forKey key: String) -> String? { values[key] }

    func set(_ value: String?, forKey key: String) {
        values[key] = value
    }
}

/// An in-memory activity log.
final class FakeActivityStore: ActivityPersisting {
    var lines: [String] = []
    private(set) var rewrites = 0

    func append(line: String) {
        lines.append(line)
    }

    func readLines() -> [String] { lines }

    func rewrite(lines newLines: [String]) {
        lines = newLines
        rewrites += 1
    }
}

/// An in-memory rules file.
final class FakeRulesFile: RulesFileAccessing {
    let path = "/fake/rules.json"
    var contents: Data?
    private(set) var writes: [Data] = []

    func read() -> Data? { contents }

    func write(_ data: Data) {
        contents = data
        writes.append(data)
    }
}

/// A watcher that records target sets and exposes its callbacks.
final class FakeWatcher: TargetWatching {
    private(set) var targetSets: [[String]] = []
    var onTargetEvent: ((String, String) -> Void)?
    var onRulesFileEvent: (() -> Void)?

    func setTargets(_ directories: [String]) {
        targetSets.append(directories)
    }
}

/// A fetcher that answers from canned responses, synchronously.
final class FakeUpdateFetcher: UpdateFetching {
    var fetchResponse: Data?
    var downloadResponse: String?
    private(set) var fetchedURLs: [String] = []
    private(set) var downloadedURLs: [String] = []

    func fetch(url: String, completion: @escaping (Data?) -> Void) {
        fetchedURLs.append(url)
        completion(fetchResponse)
    }

    func download(url: String, completion: @escaping (String?) -> Void) {
        downloadedURLs.append(url)
        completion(downloadResponse)
    }
}

/// An installer that records requests and reports a canned failure.
final class FakeUpdateInstaller: UpdateInstalling {
    var failure: String?
    var callsCompletion = true
    private(set) var installedZips: [String] = []

    func install(zipPath: String, completion: @escaping (String?) -> Void) {
        installedZips.append(zipPath)
        if callsCompletion { completion(failure) }
    }
}

/// Convenience factories for facts used across suites.
enum Fixtures {
    /// A file fact with every date defaulting to the epoch-ish base instant.
    static func file(
        _ path: String,
        size: UInt64 = 100,
        isDirectory: Bool = false,
        created: Date = Date(timeIntervalSince1970: 1_000_000),
        modified: Date = Date(timeIntervalSince1970: 1_000_000),
        added: Date = Date(timeIntervalSince1970: 1_000_000)
    ) -> FileFacts {
        FileFacts(
            path: path, name: (path as NSString).lastPathComponent, isDirectory: isDirectory,
            size: size, created: created, modified: modified, added: added)
    }
}
