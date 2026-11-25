import AppKit
import Darwin
import Foundation

/// `NSApplicationMain` only installs a delegate when `NSPrincipalClass` is that class.
/// The generated Info.plist does not set it, so the updater was staying alive and doing nothing.
@main
enum VermailUpdaterEntry {
    static func main() {
        let application = NSApplication.shared
        let delegate = VermailUpdaterMain()
        application.setActivationPolicy(.regular)
        application.delegate = delegate
        application.run()
    }
}

@MainActor
final class VermailUpdaterMain: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_: Notification) {
        if UpdateReplacer.bundleIsInsideHostApplication(Bundle.main.bundleURL) {
            relocate()
            return
        }
        showProgress()
        Task { await self.install() }
    }

    private func relocate() {
        do {
            let copy = try UpdateReplacer.temporaryCopy(of: Bundle.main.bundleURL)
            let configuration = UpdateReplacer.foregroundLaunch()
            configuration.arguments = [UpdateJobLocation.file.path(percentEncoded: false)]
            NSWorkspace.shared.openApplication(at: copy, configuration: configuration) { _, error in
                if let error {
                    fputs("\(error.localizedDescription)\n", stderr)
                }
                exit(error == nil ? 0 : 1)
            }
        } catch {
            fputs("\(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private func install() async {
        do {
            let job = try readJob()
            guard await parentHasExited(job.parentPID) else {
                throw UpdateReplaceError.commandFailed("Vermail did not quit.")
            }
            let unpacked = FileManager.default.temporaryDirectory
                .appending(path: "VermailUpdate-\(UUID().uuidString)", directoryHint: .isDirectory)
            let application = try unpackedApplication(job: job, directory: unpacked)
            let destination = URL(fileURLWithPath: job.destinationPath)
            try UpdateReplacer.install(application: application, replacing: destination)
            relaunch(destination)
        } catch {
            fail(error.localizedDescription)
        }
    }

    private func readJob() throws -> UpdateJob {
        let path = CommandLine.arguments.count >= 2
            ? CommandLine.arguments[1]
            : UpdateJobLocation.file.path(percentEncoded: false)
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let job = try JSONDecoder().decode(UpdateJob.self, from: data)
        let destination = URL(fileURLWithPath: job.destinationPath)
        guard job.parentPID > 0, destination.lastPathComponent == "Vermail.app" else {
            throw UpdateReplaceError.commandFailed("unsafe update job")
        }
        return job
    }

    private func parentHasExited(_ pid: Int32) async -> Bool {
        let deadline = Date().addingTimeInterval(90)
        while Date() < deadline {
            if kill(pid, 0) != 0 {
                return true
            }
            try? await Task.sleep(for: .milliseconds(200))
        }
        return false
    }

    private func unpackedApplication(job: UpdateJob, directory: URL) throws -> URL {
        try UpdateReplacer.unzip(URL(fileURLWithPath: job.zipPath), into: directory)
        guard let application = UpdateReplacer.application(in: directory) else {
            throw UpdateReplaceError.commandFailed("Vermail.app was not in the archive")
        }
        return application
    }

    private func relaunch(_ destination: URL) {
        let configuration = UpdateReplacer.foregroundLaunch()
        configuration.arguments = ["--foreground"]
        NSWorkspace.shared.openApplication(at: destination, configuration: configuration) { running, error in
            if running == nil {
                fputs("\(error?.localizedDescription ?? "launch failed")\n", stderr)
                exit(1)
            }
            exit(0)
        }
    }

    private func fail(_ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = String(localized: "The update could not be installed.")
        alert.informativeText = message
        alert.addButton(withTitle: String(localized: "OK"))
        alert.runModal()
        exit(1)
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
        window.level = .floating
        window.center()
        window.orderFrontRegardless()
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
    }
}
