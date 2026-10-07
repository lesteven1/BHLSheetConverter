import AppKit
import Foundation
import Darwin

private let weekdays = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]
private let requiredHeaders = [
    "Order ID",
    "Lineitem quantity",
    "Lineitem name",
    "Lineitem variant",
    "Checkout Form: Student Name",
    "Checkout Form: Student Number"
]

enum SheetMachineError: LocalizedError {
    case unreadableCSV
    case missingColumns([String])
    case noMatchingRows(String)

    var errorDescription: String? {
        switch self {
        case .unreadableCSV:
            return "The CSV could not be read."
        case .missingColumns(let columns):
            return "This does not look like a Squarespace orders export. Missing: \(columns.joined(separator: ", "))."
        case .noMatchingRows(let day):
            return "No \(day) items or Order Every Day items were found."
        }
    }
}

struct CSVDocument {
    let rows: [[String]]

    static func read(from url: URL) throws -> CSVDocument {
        let data = try Data(contentsOf: url)
        guard var text = String(data: data, encoding: .utf8) else {
            throw SheetMachineError.unreadableCSV
        }
        if text.hasPrefix("\u{FEFF}") {
            text.removeFirst()
        }
        return CSVDocument(rows: parse(text))
    }

    private static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]
            if inQuotes {
                if character == "\"" {
                    let next = text.index(after: index)
                    if next < text.endIndex && text[next] == "\"" {
                        field.append("\"")
                        index = next
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(character)
                }
            } else {
                switch character {
                case "\"":
                    inQuotes = true
                case ",":
                    row.append(field)
                    field = ""
                case "\n":
                    row.append(field)
                    rows.append(row)
                    row = []
                    field = ""
                case "\r":
                    break
                default:
                    field.append(character)
                }
            }
            index = text.index(after: index)
        }

        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }

    static func write(rows: [[String]], to url: URL) throws {
        let body = rows.map { row in
            row.map(escape).joined(separator: ",")
        }.joined(separator: "\r\n") + "\r\n"
        guard let data = ("\u{FEFF}" + body).data(using: .utf8) else {
            throw SheetMachineError.unreadableCSV
        }
        try data.write(to: url, options: .atomic)
    }

    private static func escape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }
}

struct OrderProcessor {
    static func isSquarespaceOrdersCSV(_ url: URL) -> Bool {
        guard let document = try? CSVDocument.read(from: url), let header = document.rows.first else {
            return false
        }
        return requiredHeaders.allSatisfy(header.contains)
    }

    static func process(input: URL, day: String, requestedOutput: URL? = nil) throws -> (url: URL, rowCount: Int, quantity: Int) {
        let document = try CSVDocument.read(from: input)
        guard let header = document.rows.first else { throw SheetMachineError.unreadableCSV }

        let headerMap = Dictionary(uniqueKeysWithValues: header.enumerated().map { ($1, $0) })
        let missing = requiredHeaders.filter { headerMap[$0] == nil }
        guard missing.isEmpty else { throw SheetMachineError.missingColumns(missing) }

        func value(_ row: [String], _ column: String) -> String {
            guard let columnIndex = headerMap[column], columnIndex < row.count else { return "" }
            return row[columnIndex].trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var studentsByOrder: [String: (name: String, number: String)] = [:]
        for row in document.rows.dropFirst() {
            let orderID = value(row, "Order ID")
            guard !orderID.isEmpty else { continue }
            let name = value(row, "Checkout Form: Student Name")
            let number = value(row, "Checkout Form: Student Number")
            if !name.isEmpty || !number.isEmpty {
                studentsByOrder[orderID] = (name, number)
            }
        }

        let normalizedDay = day.lowercased()
        var dataRows: [[String]] = []
        var totalQuantity = 0

        for row in document.rows.dropFirst() {
            let itemName = value(row, "Lineitem name")
            let normalizedItem = itemName.lowercased()
            let containsDay = normalizedItem.range(
                of: "\\b\(NSRegularExpression.escapedPattern(for: normalizedDay))\\b",
                options: .regularExpression
            ) != nil
            let isEveryDay = normalizedItem.range(
                of: "\\border\\s+every\\s*day\\b",
                options: .regularExpression
            ) != nil
            guard containsDay || isEveryDay else { continue }

            let orderID = value(row, "Order ID")
            let savedStudent = studentsByOrder[orderID]
            let directName = value(row, "Checkout Form: Student Name")
            let directNumber = value(row, "Checkout Form: Student Number")
            let name = directName.isEmpty ? (savedStudent?.name ?? "") : directName
            let number = directNumber.isEmpty ? (savedStudent?.number ?? "") : directNumber
            let quantityText = value(row, "Lineitem quantity")
            totalQuantity += Int(quantityText) ?? 0

            dataRows.append([
                name,
                quantityText,
                number,
                value(row, "Lineitem variant")
            ])
        }

        guard !dataRows.isEmpty else { throw SheetMachineError.noMatchingRows(day) }
        dataRows.sort { left, right in
            let leftName = left[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let rightName = right[0].trimmingCharacters(in: .whitespacesAndNewlines)
            if leftName.isEmpty != rightName.isEmpty {
                return !leftName.isEmpty
            }
            return leftName.localizedCaseInsensitiveCompare(rightName) == .orderedAscending
        }

        let outputRows = [
            ["Total Quantity", String(totalQuantity), "", ""],
            ["", "", "", ""],
            ["Name", "Quantity", "Student Number", "Variant"]
        ] + dataRows
        let outputURL = requestedOutput ?? uniqueOutputURL(for: input, day: day)
        try CSVDocument.write(rows: outputRows, to: outputURL)
        return (outputURL, dataRows.count, totalQuantity)
    }

    private static func uniqueOutputURL(for input: URL, day: String) -> URL {
        let folder = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
        let base = day
        var candidate = folder.appendingPathComponent(base).appendingPathExtension("csv")
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(base) (\(counter))").appendingPathExtension("csv")
            counter += 1
        }
        return candidate
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var monitor: DispatchSourceFileSystemObject?
    private var directoryFileDescriptor: Int32 = -1
    private var scanWorkItem: DispatchWorkItem?
    private var isScanning = false
    private var scanAgain = false
    private var knownSignatures = Set<String>()
    private var lastOutputURL: URL?

    private let fileManager = FileManager.default
    private lazy var downloadsURL = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
    private lazy var supportURL: URL = {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SheetMachine", isDirectory: true)
    }()
    private lazy var stateURL = supportURL.appendingPathComponent("seen-downloads.json")

    func applicationDidFinishLaunching(_ notification: Notification) {
        if NSRunningApplication.runningApplications(withBundleIdentifier: "com.bhl.sheetmachine")
            .contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            NSApp.terminate(nil)
            return
        }
        NSApp.setActivationPolicy(.accessory)
        setUpMenuBar()
        loadOrInitializeState()
        startMonitoringDownloads()
        scheduleScan(after: 0.8)
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor?.cancel()
        if directoryFileDescriptor >= 0 {
            close(directoryFileDescriptor)
        }
    }

    private func setUpMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "tablecells", accessibilityDescription: "Sheet Machine")
            button.toolTip = "Sheet Machine"
        }

        let menu = NSMenu()
        let watching = NSMenuItem(title: "Watching Downloads", action: nil, keyEquivalent: "")
        watching.isEnabled = false
        menu.addItem(watching)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Process a CSV…", action: #selector(selectCSV), keyEquivalent: "o"))
        menu.addItem(NSMenuItem(title: "Reveal Last Output", action: #selector(revealLastOutput), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "Open Downloads", action: #selector(openDownloads), keyEquivalent: "d"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Sheet Machine", action: #selector(quit), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        statusItem.menu = menu
        updateRevealMenuItem()
    }

    private func startMonitoringDownloads() {
        directoryFileDescriptor = open(downloadsURL.path, O_EVTONLY)
        guard directoryFileDescriptor >= 0 else {
            showError(title: "Downloads access is required", message: "Sheet Machine could not watch your Downloads folder. Open the app again and allow Downloads access when macOS asks.")
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: directoryFileDescriptor,
            eventMask: [.write, .extend, .attrib, .rename],
            queue: .main
        )
        source.setEventHandler { [weak self] in self?.scheduleScan(after: 1.2) }
        source.setCancelHandler { }
        source.resume()
        monitor = source
    }

    private func scheduleScan(after delay: TimeInterval) {
        scanWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.scanDownloads() }
        scanWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func scanDownloads() {
        if isScanning {
            scanAgain = true
            return
        }
        isScanning = true

        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        let urls = (try? fileManager.contentsOfDirectory(
            at: downloadsURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        )) ?? []

        let candidates = urls.filter { $0.pathExtension.lowercased() == "csv" }
            .sorted { modificationDate(for: $0) < modificationDate(for: $1) }
            .filter { !knownSignatures.contains(signature(for: $0)) }

        processCandidates(candidates, at: 0)
    }

    private func processCandidates(_ candidates: [URL], at index: Int) {
        guard index < candidates.count else {
            isScanning = false
            if scanAgain {
                scanAgain = false
                scheduleScan(after: 0.5)
            }
            return
        }

        let url = candidates[index]
        let firstSignature = signature(for: url)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self else { return }
            let stableSignature = self.signature(for: url)
            guard firstSignature == stableSignature,
                  self.fileManager.fileExists(atPath: url.path) else {
                self.processCandidates(candidates, at: index + 1)
                self.scheduleScan(after: 1.0)
                return
            }

            self.knownSignatures.insert(stableSignature)
            self.saveState()

            guard OrderProcessor.isSquarespaceOrdersCSV(url) else {
                self.processCandidates(candidates, at: index + 1)
                return
            }

            guard let day = self.askForDay(fileName: url.lastPathComponent) else {
                self.processCandidates(candidates, at: index + 1)
                return
            }

            do {
                let result = try OrderProcessor.process(input: url, day: day)
                self.lastOutputURL = result.url
                self.updateRevealMenuItem()
                self.showCompletion(day: day, result: result)
            } catch {
                self.showError(title: "Could not create the sheet", message: error.localizedDescription)
            }
            self.processCandidates(candidates, at: index + 1)
        }
    }

    private func askForDay(fileName: String) -> String? {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Which day is this sheet for?"
        alert.informativeText = "\(fileName)\n\nThe sheet will include that weekday’s item and every Order Every Day item."
        alert.addButton(withTitle: "Create Sheet")
        alert.addButton(withTitle: "Skip")

        let picker = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 220, height: 28), pullsDown: false)
        picker.addItems(withTitles: weekdays)
        let currentDay = Calendar.current.component(.weekday, from: Date())
        let currentIndex = [2: 0, 3: 1, 4: 2, 5: 3, 6: 4][currentDay] ?? 0
        picker.selectItem(at: currentIndex)
        alert.accessoryView = picker

        return alert.runModal() == .alertFirstButtonReturn ? picker.titleOfSelectedItem : nil
    }

    private func showCompletion(day: String, result: (url: URL, rowCount: Int, quantity: Int)) {
        let notification = NSUserNotification()
        notification.title = "\(day) sheet created"
        notification.informativeText = "Saved \(result.rowCount) rows (\(result.quantity) items) as \(result.url.lastPathComponent)."
        notification.soundName = NSUserNotificationDefaultSoundName
        NSUserNotificationCenter.default.deliver(notification)
    }

    private func showError(title: String, message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func signature(for url: URL) -> String {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let timestamp = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
        let size = values?.fileSize ?? -1
        return "\(url.path)|\(size)|\(timestamp)"
    }

    private func modificationDate(for url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
    }

    private func loadOrInitializeState() {
        try? fileManager.createDirectory(at: supportURL, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: stateURL),
           let saved = try? JSONDecoder().decode([String].self, from: data) {
            knownSignatures = Set(saved)
            return
        }

        let existing = (try? fileManager.contentsOfDirectory(
            at: downloadsURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        knownSignatures = Set(existing.filter { $0.pathExtension.lowercased() == "csv" }.map(signature))
        saveState()
    }

    private func saveState() {
        let recent = Array(knownSignatures.suffix(1_000))
        if let data = try? JSONEncoder().encode(recent) {
            try? data.write(to: stateURL, options: .atomic)
        }
    }

    private func updateRevealMenuItem() {
        guard let item = statusItem.menu?.items.first(where: { $0.action == #selector(revealLastOutput) }) else { return }
        item.isEnabled = lastOutputURL != nil
    }

    @objc private func selectCSV() {
        let panel = NSOpenPanel()
        panel.title = "Choose a Squarespace orders CSV"
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.allowsMultipleSelection = false
        panel.directoryURL = downloadsURL
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard OrderProcessor.isSquarespaceOrdersCSV(url) else {
            showError(title: "Not a Squarespace orders CSV", message: "The required Squarespace order columns were not found.")
            return
        }
        guard let day = askForDay(fileName: url.lastPathComponent) else { return }
        do {
            let result = try OrderProcessor.process(input: url, day: day)
            lastOutputURL = result.url
            updateRevealMenuItem()
            showCompletion(day: day, result: result)
        } catch {
            showError(title: "Could not create the sheet", message: error.localizedDescription)
        }
    }

    @objc private func revealLastOutput() {
        guard let lastOutputURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([lastOutputURL])
    }

    @objc private func openDownloads() {
        NSWorkspace.shared.open(downloadsURL)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

private func runCommandLineMode(arguments: [String]) -> Int32? {
    guard arguments.contains("--process") else { return nil }

    func argument(after flag: String) -> String? {
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    guard let inputPath = argument(after: "--process"),
          let day = argument(after: "--day"),
          weekdays.contains(day) else {
        fputs("Usage: SheetMachine --process input.csv --day Monday [--output output.csv]\n", stderr)
        return 2
    }

    let output = argument(after: "--output").map { URL(fileURLWithPath: $0) }
    do {
        let result = try OrderProcessor.process(input: URL(fileURLWithPath: inputPath), day: day, requestedOutput: output)
        print("\(result.url.path)\t\(result.rowCount)\t\(result.quantity)")
        return 0
    } catch {
        fputs("\(error.localizedDescription)\n", stderr)
        return 1
    }
}

if let exitCode = runCommandLineMode(arguments: CommandLine.arguments) {
    exit(exitCode)
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
