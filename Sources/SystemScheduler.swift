// SystemScheduler.swift
// DispatchSourceTimer behind the Scheduler port. Excluded from coverage;
// audited by scripts/shim-audit.py.

import Foundation

/// A cancellable wrapping one dispatch timer.
private final class TimerHandle: Cancellable {
    let timer: DispatchSourceTimer

    init(_ timer: DispatchSourceTimer) {
        self.timer = timer
    }

    func cancel() {
        timer.cancel()
    }
}

/// Real timers, delivered on the main queue (the coordinator is main-thread-confined).
final class SystemScheduler: Scheduler {

    func schedule(after seconds: TimeInterval, _ handler: @escaping () -> Void) -> Cancellable {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + seconds)
        timer.setEventHandler { [weak timer] in
            handler()
            timer?.cancel()
        }
        timer.resume()
        return TimerHandle(timer)
    }

    func every(seconds: TimeInterval, _ handler: @escaping () -> Void) -> Cancellable {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + seconds, repeating: seconds)
        timer.setEventHandler(handler: handler)
        timer.resume()
        return TimerHandle(timer)
    }
}
