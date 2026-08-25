// UpdateInstaller.swift
// Swaps the running bundle for a downloaded one and relaunches. The swap runs
// in a detached shell that outlives this process: remove the old bundle, move
// the new one into place, open it. Whether to install at all is decided in the
// covered core; this only executes.
// Excluded from coverage; audited by scripts/shim-audit.py.

import AppKit
import Foundation

/// Real bundle replacement.
final class UpdateInstaller: UpdateInstalling {

    func install(zipPath: String, completion: @escaping (String?) -> Void) {
        let staging = NSTemporaryDirectory() + "whisk-update-\(ProcessInfo.processInfo.globallyUniqueString)"
        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        unzip.arguments = ["-xk", zipPath, staging]
        do {
            try unzip.run()
        } catch {
            completion("could not launch ditto: \(error.localizedDescription)")
            return
        }
        unzip.waitUntilExit()
        let newApp = staging + "/Whisk.app"
        guard unzip.terminationStatus == 0, FileManager.default.fileExists(atPath: newApp + "/Contents/MacOS/Whisk") else {
            completion("the downloaded archive did not contain a valid Whisk.app")
            return
        }

        // Positional args keep paths out of shell-string interpolation; the
        // swapper survives this process exiting because it is its own session.
        let swap = Process()
        swap.executableURL = URL(fileURLWithPath: "/bin/sh")
        swap.arguments = ["-c", #"sleep 0.5; rm -rf "$1"; mv "$2" "$1"; open "$1""#, "_", Bundle.main.bundlePath, newApp]
        do {
            try swap.run()
        } catch {
            completion("could not launch the update swapper: \(error.localizedDescription)")
            return
        }
        NSApplication.shared.terminate(nil)
    }
}
