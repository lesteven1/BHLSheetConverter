import AppKit
import Foundation

enum InstallerError: LocalizedError {
    case missingBundledApp
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingBundledApp:
            return "The Sheet Machine app is missing from this installer."
        case .commandFailed(let message):
            return message
        }
    }
}

final class InstallerDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        let confirmation = NSAlert()
        confirmation.messageText = "Install Sheet Machine?"
        confirmation.informativeText = "This installs Sheet Machine in your personal Applications folder, starts it now, and opens it automatically when you log in."
        confirmation.addButton(withTitle: "Install")
        confirmation.addButton(withTitle: "Cancel")

        guard confirmation.runModal() == .alertFirstButtonReturn else {
            NSApp.terminate(nil)
            return
        }

        do {
            try install()
            let success = NSAlert()
            success.messageText = "Sheet Machine is installed"
            success.informativeText = "It is now watching Downloads. The next Squarespace orders CSV you download will ask which weekday to create, then save the cleaned sheet on the Desktop."
            success.addButton(withTitle: "Done")
            success.runModal()
        } catch {
            let failure = NSAlert()
            failure.alertStyle = .critical
            failure.messageText = "Installation failed"
            failure.informativeText = error.localizedDescription
            failure.addButton(withTitle: "OK")
            failure.runModal()
        }

        NSApp.terminate(nil)
    }

    private func install() throws {
        let fileManager = FileManager.default
        guard let resources = Bundle.main.resourceURL else {
            throw InstallerError.missingBundledApp
        }

        let bundledApp = resources.appendingPathComponent("Sheet Machine.app", isDirectory: true)
        let bundledExecutable = bundledApp.appendingPathComponent("Contents/MacOS/SheetMachine")
        guard fileManager.fileExists(atPath: bundledExecutable.path) else {
            throw InstallerError.missingBundledApp
        }

        let userHome = fileManager.homeDirectoryForCurrentUser
        let applications = userHome.appendingPathComponent("Applications", isDirectory: true)
        let installedApp = applications.appendingPathComponent("Sheet Machine.app", isDirectory: true)
        let installedExecutable = installedApp.appendingPathComponent("Contents/MacOS/SheetMachine")
        let launchAgents = userHome.appendingPathComponent("Library/LaunchAgents", isDirectory: true)
        let launchAgent = launchAgents.appendingPathComponent("com.bhl.sheetmachine.plist")
        let domain = "gui/\(getuid())"

        try fileManager.createDirectory(at: applications, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: launchAgents, withIntermediateDirectories: true)

        _ = try? run("/bin/launchctl", ["bootout", domain, launchAgent.path])
        _ = try? run("/usr/bin/pkill", ["-x", "SheetMachine"])

        if fileManager.fileExists(atPath: installedApp.path) {
            try fileManager.removeItem(at: installedApp)
        }
        try fileManager.copyItem(at: bundledApp, to: installedApp)
        _ = try? run("/usr/bin/xattr", ["-cr", installedApp.path])

        let configuration: [String: Any] = [
            "Label": "com.bhl.sheetmachine",
            "ProgramArguments": [installedExecutable.path],
            "RunAtLoad": true,
            "ProcessType": "Interactive",
            "LimitLoadToSessionType": "Aqua",
            "ThrottleInterval": 10
        ]
        let plistData = try PropertyListSerialization.data(
            fromPropertyList: configuration,
            format: .xml,
            options: 0
        )
        try plistData.write(to: launchAgent, options: .atomic)

        let bootstrap = try run("/bin/launchctl", ["bootstrap", domain, launchAgent.path])
        guard bootstrap.status == 0 else {
            throw InstallerError.commandFailed(bootstrap.message)
        }
        _ = try? run("/bin/launchctl", ["kickstart", "-k", "\(domain)/com.bhl.sheetmachine"])
    }

    private func run(_ executable: String, _ arguments: [String]) throws -> (status: Int32, message: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let message = output.isEmpty ? "A macOS setup command failed with status \(process.terminationStatus)." : output
        return (process.terminationStatus, message)
    }
}

let application = NSApplication.shared
let delegate = InstallerDelegate()
application.delegate = delegate
application.run()
