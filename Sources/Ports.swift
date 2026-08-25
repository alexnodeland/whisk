// Ports.swift
// The protocols (hexagonal "ports") through which the pure core reaches the
// outside world. Real conformances are thin shims (excluded from coverage);
// tests use fakes. In coverage. Imports only Foundation.

import Foundation

/// A handle that cancels a scheduled timer.
protocol Cancellable: AnyObject {
    func cancel()
}

/// Wall clock, injected so the core never calls `Date()` directly.
protocol Clock: AnyObject {
    /// The current wall-clock instant.
    func now() -> Date
}

/// Cancellable timers used for sweep debounce, age wake-ups, and the rescan cadence.
protocol Scheduler: AnyObject {
    /// Fire `handler` once after `seconds`. Returns a handle to cancel it.
    func schedule(after seconds: TimeInterval, _ handler: @escaping () -> Void) -> Cancellable
    /// Fire `handler` every `seconds` until cancelled. Returns a handle.
    func every(seconds: TimeInterval, _ handler: @escaping () -> Void) -> Cancellable
}

/// Reads directory contents as immutable metadata snapshots.
protocol DirectoryEnumerating: AnyObject {
    /// Metadata for every entry directly inside `directory`, or nil if unreadable.
    func facts(inDirectory directory: String) -> [FileFacts]?
    /// The entry names directly inside `directory`, or nil if unreadable.
    func names(inDirectory directory: String) -> [String]?
}

/// A filesystem effect failure, phrased for the activity log.
struct FileOpError: Error, Equatable {
    /// What went wrong.
    var message: String
}

/// Executes filesystem effects. Every method returns the final absolute path on
/// success or a failure message; no method decides anything.
protocol FileActing: AnyObject {
    /// Create `directory` (and intermediates) if missing.
    func ensureDirectory(_ directory: String) -> Result<String, FileOpError>
    /// Move `source` to `destination` (a full file path, not a directory).
    func move(_ source: String, to destination: String) -> Result<String, FileOpError>
    /// Copy `source` to `destination` (a full file path, not a directory).
    func copy(_ source: String, to destination: String) -> Result<String, FileOpError>
    /// Remove `path`, replacing-style, used only for the `.replace` conflict policy.
    func remove(_ path: String) -> Result<String, FileOpError>
    /// Send `path` to the Trash. Success carries the item's new Trash path.
    func trash(_ path: String) -> Result<String, FileOpError>
}

/// Runs an approved shell command with a sanitized environment and a timeout.
protocol CommandRunning: AnyObject {
    /// Execute `command` with `arguments`, working directory `directory`, and
    /// extra environment `environment`. Calls `completion` with (exitCode,
    /// truncated combined output); exitCode is nil when the launch itself failed
    /// or the timeout killed the process.
    func run(
        command: String,
        arguments: [String],
        directory: String,
        environment: [String: String],
        timeout: TimeInterval,
        completion: @escaping (Int32?, String) -> Void
    )
}

/// Posts user notifications.
protocol Notifying: AnyObject {
    /// Deliver a notification with `title` and `body`.
    func post(title: String, body: String)
}

/// String-keyed persistence for settings and small state blobs.
protocol KeyValueStore: AnyObject {
    /// The stored string for `key`, or nil.
    func string(forKey key: String) -> String?
    /// Store `value` under `key`; nil removes it.
    func set(_ value: String?, forKey key: String)
}

/// Appends and rewrites the activity log (a JSONL file).
protocol ActivityPersisting: AnyObject {
    /// Append one line to the log.
    func append(line: String)
    /// All current lines, oldest first; empty if the log is missing.
    func readLines() -> [String]
    /// Atomically replace the log with `lines`.
    func rewrite(lines: [String])
}

/// Reads and writes the user's rules file.
protocol RulesFileAccessing: AnyObject {
    /// The rules file's absolute path (for display and "Open Rules File").
    var path: String { get }
    /// The file's bytes, or nil if it does not exist.
    func read() -> Data?
    /// Atomically write `data` to the rules file, creating parent directories.
    func write(_ data: Data)
}

/// Fetches update metadata and downloads release archives over HTTPS.
protocol UpdateFetching: AnyObject {
    /// GET `url` and deliver the body on the main queue, or nil on any failure.
    func fetch(url: String, completion: @escaping (Data?) -> Void)
    /// Download `url` to a temporary file and deliver its path on the main
    /// queue, or nil on any failure.
    func download(url: String, completion: @escaping (String?) -> Void)
}

/// Replaces the running app bundle with an unpacked update and relaunches.
protocol UpdateInstalling: AnyObject {
    /// Unpack `zipPath`, swap the bundle, and relaunch. Calls `completion` with
    /// an error message only on failure — on success the process exits.
    func install(zipPath: String, completion: @escaping (String?) -> Void)
}

/// Watches target directories and the rules file, reporting raw change events.
protocol TargetWatching: AnyObject {
    /// Replace the set of watched target directories.
    func setTargets(_ directories: [String])
    /// Called with (target directory, affected path) when something inside a
    /// watched target changes.
    var onTargetEvent: ((String, String) -> Void)? { get set }
    /// Called when the rules file itself changes.
    var onRulesFileEvent: (() -> Void)? { get set }
}
