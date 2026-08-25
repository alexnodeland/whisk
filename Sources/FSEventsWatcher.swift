// FSEventsWatcher.swift
// FSEventStream (per-file events, coalesced) for the watched targets, plus a
// vnode watch on the rules file, behind the TargetWatching port. Which target
// an event belongs to is a longest-prefix lookup; everything downstream
// (debounce, self-write drop, sweeping) is decided in the covered core.
// Excluded from coverage; audited by scripts/shim-audit.py.

import CoreServices
import Foundation

/// Real filesystem watching.
final class FSEventsWatcher: TargetWatching {

    var onTargetEvent: ((String, String) -> Void)?
    var onRulesFileEvent: (() -> Void)?

    private let rulesFilePath: String
    private var stream: FSEventStreamRef?
    private var roots: [String] = []
    private var rulesSource: DispatchSourceFileSystemObject?

    init(rulesFilePath: String) {
        self.rulesFilePath = rulesFilePath
        watchRulesFile()
    }

    deinit {
        stopStream()
        rulesSource?.cancel()
    }

    func setTargets(_ directories: [String]) {
        roots = directories
        stopStream()
        guard !directories.isEmpty else { return }

        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            let watcher = Unmanaged<FSEventsWatcher>.fromOpaque(info!).takeUnretainedValue()
            let cfPaths = Unmanaged<CFArray>.fromOpaque(paths).takeUnretainedValue() as! [String]
            (0..<count).forEach { watcher.dispatch(path: cfPaths[$0]) }
        }
        let created = FSEventStreamCreate(
            nil, callback, &context, directories as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            SweepScheduler.eventDebounce,
            UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes))
        guard let created else { return }
        stream = created
        FSEventStreamSetDispatchQueue(created, .main)
        FSEventStreamStart(created)
    }

    /// Route one event path to the target root that contains it (decided in the
    /// covered core).
    private func dispatch(path: String) {
        SweepCoordinator.targetRoot(forEventPath: path, roots: roots).map { onTargetEvent?($0, path) }
    }

    private func stopStream() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    /// Watch the rules file with a vnode source, re-arming after atomic saves
    /// (which replace the file, delivering .delete/.rename on the old node).
    private func watchRulesFile() {
        let fd = open(rulesFilePath, O_EVTONLY)
        guard fd >= 0 else {
            // The file may not exist yet (first launch seeds it): retry shortly.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.watchRulesFile() }
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .delete, .rename], queue: .main)
        source.setEventHandler { [weak self] in
            let events = source.data
            self?.onRulesFileEvent?()
            if !events.isDisjoint(with: [.delete, .rename]) {
                source.cancel()
                self?.watchRulesFile()
            }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        rulesSource = source
    }
}
