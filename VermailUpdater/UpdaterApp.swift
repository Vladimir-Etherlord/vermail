import AppKit
import Foundation

@main
@MainActor
final class VermailUpdaterMain: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_: Notification) {
        guard CommandLine.arguments.count >= 2 else {
            NSApp.terminate(nil)
            return
        }
        showProgress()
        let jobPath = CommandLine.arguments[1]
        Task {
            await self.install(jobPath: jobPath)
        }
    }

    private func install(jobPath: String) async {
        do {
            let job = try readJob(at: jobPath)
            guard await waitUntilExits(job.parentPID) else {
                alert(String(localized: "Vermail is still open. Quit it and try the update again."))
                NSApp.terminate(nil)
                return
            }
            let unpacked = FileManager.default.temporaryDirectory
                .appending(path: "VermailUpdate-\(UUID().uuidString)", directoryHint: .isDirectory)
            let application = try await Task.detached {
                try Self.unpackedApplication(job: job, directory: unpacked)
            }.value
            try UpdateReplacer.replace(
                UpdateReplacement(
                    application: application,
                    destination: URL(fileURLWithPath: job.destinationPath),
                    parentPID: job.parentPID,
                    helperPID: ProcessInfo.processInfo.processIdentifier
                ),
                finish: .relaunch
            )
            NSApp.terminate(nil)
        } catch {
            alert(String(localized: "The update could not be installed."))
            NSApp.terminate(nil)
        }
    }

    private func readJob(at path: String) throws -> UpdateJob {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let job = try JSONDecoder().decode(UpdateJob.self, from: data)
        guard job.parentPID > 0, URL(fileURLWithPath: job.destinationPath).lastPathComponent == "Vermail.app" else {
            throw UpdateReplaceError.commandFailed("unsafe update job")
        }
        return job
    }

    private nonisolated static func unpackedApplication(job: UpdateJob, directory: URL) throws -> URL {
        try UpdateReplacer.unzip(URL(fileURLWithPath: job.zipPath), into: directory)
        guard let application = UpdateReplacer.application(in: directory) else {
            throw UpdateReplaceError.commandFailed("Vermail.app was not in the archive")
        }
        return application
    }

    private func waitUntilExits(_ pid: Int32) async -> Bool {
        for _ in 0 ..< 300 {
            if kill(pid, 0) != 0 {
                return true
            }
            try? await Task.sleep(for: .milliseconds(200))
        }
        return false
    }

    private func showProgress() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 110),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "Installing Update")
        let label = NSTextField(wrappingLabelWithString: String(
            localized: "Vermail will reopen when the update is in place."
        ))
        label.frame = NSRect(x: 20, y: 16, width: 380, height: 48)
        let indicator = NSProgressIndicator(frame: NSRect(x: 20, y: 70, width: 380, height: 20))
        indicator.style = .bar
        indicator.isIndeterminate = true
        indicator.startAnimation(nil)
        window.contentView?.addSubview(indicator)
        window.contentView?.addSubview(label)
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
        NSApp.activate()
    }

    private func alert(_ message: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: String(localized: "OK"))
        alert.runModal()
    }
}
