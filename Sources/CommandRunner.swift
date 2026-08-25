// CommandRunner.swift
// Process behind the CommandRunning port: argv-only execution (never a shell),
// with the sanitized environment the coordinator built, a timeout escalation
// (SIGTERM, then SIGKILL), and captured, truncated output.
// Excluded from coverage; audited by scripts/shim-audit.py.

import Foundation

/// Runs approved shell commands.
final class CommandRunner: CommandRunning {

    /// Captured output is truncated to this many bytes.
    static let outputCap = 4096

    func run(
        command: String,
        arguments: [String],
        directory: String,
        environment: [String: String],
        timeout: TimeInterval,
        completion: @escaping (Int32?, String) -> Void
    ) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: directory)
        process.environment = environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice

        process.terminationHandler = { finished in
            let data = pipe.fileHandleForReading.readDataToEndOfFile().prefix(Self.outputCap)
            let output = String(decoding: data, as: UTF8.self)
            // A signal death (the timeout escalation, or an outside kill) reports
            // nil so the core logs "failed to launch or timed out".
            let code: Int32? = finished.terminationReason == .exit ? finished.terminationStatus : nil
            DispatchQueue.main.async { completion(code, output) }
        }

        do {
            try process.run()
        } catch {
            DispatchQueue.main.async { completion(nil, error.localizedDescription) }
            return
        }

        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
            guard process.isRunning else { return }
            process.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                if process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                }
            }
        }
    }
}
