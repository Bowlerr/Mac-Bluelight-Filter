import Foundation
import AppKit
import Combine
import CoreLocation

struct RedshiftSettings: Codable, Equatable {
    var binaryPath: String
    var latitude: String
    var longitude: String
    var dayTemp: Int
    var nightTemp: Int
    var gamma: String
    var brightness: String
    var useSchedule: Bool
    var scheduleStartHour: Int
    var scheduleStartMinute: Int
    var scheduleEndHour: Int
    var scheduleEndMinute: Int
    var startAtLogin: Bool

    static let `default` = RedshiftSettings(
        binaryPath: "/opt/homebrew/bin/redshift",
        latitude: "0.0000",
        longitude: "0.0000",
        dayTemp: 6500,
        nightTemp: 2700,
        gamma: "",
        brightness: "",
        useSchedule: false,
        scheduleStartHour: 20,
        scheduleStartMinute: 0,
        scheduleEndHour: 7,
        scheduleEndMinute: 0,
        startAtLogin: false
    )
}

final class RedshiftController: ObservableObject {
    @Published var settings: RedshiftSettings
    @Published private(set) var isRunning: Bool = false
    @Published private(set) var isEnabled: Bool = false
    @Published private(set) var isLocating: Bool = false
    @Published var statusMessage: String = ""

    private var process: Process?
    private var scheduleTimer: Timer?
    private var locationService: LocationService?
    private let workerQueue = DispatchQueue(label: "RedshiftController.worker", qos: .userInitiated)
    private var previouslyAppliedStartAtLogin: Bool

    init() {
        let loadedSettings = SettingsStore.load()
        self.settings = loadedSettings
        self.previouslyAppliedStartAtLogin = loadedSettings.startAtLogin
        refreshRunningState()
        setupScheduleTimer()
    }

    func setEnabled(_ enabled: Bool) {
        updateState(isEnabled: enabled)
        let settingsSnapshot = settings
        workerQueue.async { [weak self] in
            self?.setEnabledInternal(enabled, settings: settingsSnapshot)
        }
    }

    func applySettings() {
        SettingsStore.save(settings)
        let shouldRestartUnderLaunchAgent = settings.startAtLogin && !previouslyAppliedStartAtLogin
        updateLaunchAgent()
        previouslyAppliedStartAtLogin = settings.startAtLogin

        if shouldRestartUnderLaunchAgent {
            // Enabling start-at-login loads the LaunchAgent immediately, which starts
            // another app instance. Exit this one so the launchd-managed instance remains.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                NSApp.terminate(nil)
            }
            return
        }

        let settingsSnapshot = settings
        let enabledSnapshot = isEnabled
        workerQueue.async { [weak self] in
            guard let self else { return }
            if enabledSnapshot {
                self.restartRedshiftInternal(settings: settingsSnapshot)
            } else {
                self.refreshRunningStateInternal()
                self.syncWithScheduleInternal(settings: settingsSnapshot, isEnabled: enabledSnapshot)
            }
        }
    }

    func refreshRunningState() {
        workerQueue.async { [weak self] in
            self?.refreshRunningStateInternal()
        }
    }

    func resetColor() {
        let settingsSnapshot = settings
        workerQueue.async { [weak self] in
            self?.resetColorInternal(settings: settingsSnapshot)
        }
    }

    func useCurrentLocation() {
        guard !isLocating else { return }

        guard Bundle.main.bundleIdentifier != nil else {
            updateState(statusMessage: "Current location requires a bundled macOS app target with an Info.plist. This build cannot request location permission.")
            return
        }

        updateState(statusMessage: "")
        DispatchQueue.main.async {
            self.isLocating = true
        }

        let service = LocationService()
        locationService = service
        service.requestCurrentLocation { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isLocating = false
                self.locationService = nil

                switch result {
                case .success(let coordinate):
                    self.settings.latitude = Self.formattedCoordinate(coordinate.latitude)
                    self.settings.longitude = Self.formattedCoordinate(coordinate.longitude)
                case .failure(let error):
                    self.statusMessage = "Location failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func setEnabledInternal(_ enabled: Bool, settings: RedshiftSettings) {
        if enabled {
            startRedshiftInternal(settings: settings)
        } else {
            stopRedshiftInternal(settings: settings)
        }
    }

    private func startRedshiftInternal(settings: RedshiftSettings) {
        updateState(statusMessage: "")

        guard FileManager.default.fileExists(atPath: settings.binaryPath) else {
            updateState(
                isRunning: false,
                isEnabled: false,
                statusMessage: "Redshift not found at \(settings.binaryPath)"
            )
            return
        }

        if !settings.useSchedule && !hasValidCoordinates(settings: settings) {
            updateState(
                isRunning: false,
                isEnabled: false,
                statusMessage: "Enter valid latitude/longitude for Sunrise/Sunset mode, or switch to Manual Schedule."
            )
            return
        }

        if isRedshiftProcessRunning() {
            terminateAllRedshiftProcesses()
        }

        let args = buildArguments(for: settings)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: settings.binaryPath)
        process.arguments = args
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] _ in
            self?.updateState(isRunning: false, isEnabled: false)
        }

        do {
            try process.run()
            self.process = process
            updateState(isRunning: true, isEnabled: true)
        } catch {
            updateState(
                isRunning: false,
                isEnabled: false,
                statusMessage: "Failed to start redshift: \(error.localizedDescription)"
            )
        }
    }

    private func stopRedshiftInternal(settings: RedshiftSettings) {
        updateState(statusMessage: "")

        if let process = process, process.isRunning {
            process.terminationHandler = nil
            process.terminate()
        }
        self.process = nil

        terminateAllRedshiftProcesses()
        updateState(isRunning: false, isEnabled: false)
        resetColorDetached(settings: settings)
    }

    private func restartRedshiftInternal(settings: RedshiftSettings) {
        stopRedshiftInternal(settings: settings)
        startRedshiftInternal(settings: settings)
    }

    private func buildArguments(for settings: RedshiftSettings) -> [String] {
        var args: [String]
        if settings.useSchedule {
            // In manual schedule mode we only need a fixed target temperature.
            args = ["-O", "\(settings.nightTemp)", "-m", "quartz"]
        } else {
            args = [
                "-l", "\(settings.latitude):\(settings.longitude)",
                "-t", "\(settings.dayTemp):\(settings.nightTemp)",
                "-m", "quartz"
            ]
        }

        if !settings.gamma.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            args.append(contentsOf: ["-g", settings.gamma])
        }

        let brightnessArg = brightnessArgument(for: settings)
        if !brightnessArg.isEmpty {
            args.append(contentsOf: ["-b", brightnessArg])
        }

        return args
    }

    private func brightnessArgument(for settings: RedshiftSettings) -> String {
        let raw = settings.brightness.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            return ""
        }

        // Manual schedule uses a fixed -O temperature, so brightness should also be fixed.
        // If user entered day:night, choose night for manual schedule.
        if settings.useSchedule {
            let parts = raw.split(separator: ":")
            if parts.count >= 2 {
                return String(parts[1])
            }
        }

        return raw
    }

    private func hasValidCoordinates(settings: RedshiftSettings) -> Bool {
        guard
            let latitude = Double(settings.latitude),
            let longitude = Double(settings.longitude)
        else {
            return false
        }
        return (-90.0...90.0).contains(latitude) && (-180.0...180.0).contains(longitude)
    }

    private func isRedshiftProcessRunning() -> Bool {
        let result = runProcess(
            executable: "/usr/bin/pgrep",
            arguments: ["-x", "redshift"]
        )
        return result.exitCode == 0
    }

    @discardableResult
    private func runProcess(executable: String, arguments: [String]) -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return ProcessResult(exitCode: 1, output: "", error: error.localizedDescription)
        }

        let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let error = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return ProcessResult(exitCode: Int(process.terminationStatus), output: output, error: error)
    }

    private func setupScheduleTimer() {
        scheduleTimer?.invalidate()
        scheduleTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.syncWithSchedule()
        }
        syncWithSchedule()
    }

    private func syncWithSchedule() {
        let settingsSnapshot = settings
        let enabledSnapshot = isEnabled
        guard settingsSnapshot.useSchedule else { return }
        workerQueue.async { [weak self] in
            self?.syncWithScheduleInternal(settings: settingsSnapshot, isEnabled: enabledSnapshot)
        }
    }

    private func syncWithScheduleInternal(settings: RedshiftSettings, isEnabled: Bool) {
        let shouldEnable = isWithinSchedule(settings: settings)
        if shouldEnable != isEnabled {
            setEnabledInternal(shouldEnable, settings: settings)
        }
    }

    private func isWithinSchedule(settings: RedshiftSettings) -> Bool {
        let now = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let nowMinutes = (now.hour ?? 0) * 60 + (now.minute ?? 0)
        let startMinutes = settings.scheduleStartHour * 60 + settings.scheduleStartMinute
        let endMinutes = settings.scheduleEndHour * 60 + settings.scheduleEndMinute

        if startMinutes == endMinutes {
            return true
        }

        if startMinutes < endMinutes {
            return nowMinutes >= startMinutes && nowMinutes < endMinutes
        } else {
            return nowMinutes >= startMinutes || nowMinutes < endMinutes
        }
    }

    private func refreshRunningStateInternal() {
        let running = isRedshiftProcessRunning()
        updateState(isRunning: running, isEnabled: running)
    }

    private func terminateAllRedshiftProcesses() {
        _ = runProcess(
            executable: "/usr/bin/pkill",
            arguments: ["-x", "redshift"]
        )
    }

    private func resetColorInternal(settings: RedshiftSettings) {
        updateState(statusMessage: "")
        resetColorDetached(settings: settings)
    }

    private func resetColorDetached(settings: RedshiftSettings) {
        guard FileManager.default.fileExists(atPath: settings.binaryPath) else {
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: settings.binaryPath)
        process.arguments = ["-x"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }

    private func updateState(isRunning: Bool? = nil, isEnabled: Bool? = nil, statusMessage: String? = nil) {
        DispatchQueue.main.async {
            if let isRunning {
                self.isRunning = isRunning
            }
            if let isEnabled {
                self.isEnabled = isEnabled
            }
            if let statusMessage {
                self.statusMessage = statusMessage
            }
        }
    }

    private func updateLaunchAgent() {
        let manager = LaunchAgentManager()
        if settings.startAtLogin {
            guard let executablePath = Bundle.main.executablePath else {
                statusMessage = "Unable to determine app executable path."
                return
            }
            manager.install(executablePath: executablePath)
        } else {
            manager.uninstall()
        }
    }

    private static func formattedCoordinate(_ value: Double) -> String {
        String(format: "%.4f", value)
    }
}

struct ProcessResult {
    let exitCode: Int
    let output: String
    let error: String
}

enum SettingsStore {
    private static let key = "RedshiftSettings"

    static func load() -> RedshiftSettings {
        guard let data = UserDefaults.standard.data(forKey: key) else {
            return .default
        }
        if let settings = try? JSONDecoder().decode(RedshiftSettings.self, from: data) {
            return settings
        }
        return .default
    }

    static func save(_ settings: RedshiftSettings) {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

final class LaunchAgentManager {
    private let label = "com.user.redshift-menubar"

    private var plistURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    func install(executablePath: String) {
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executablePath],
            "RunAtLoad": true,
            "KeepAlive": true
        ]

        do {
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: plistURL)
            _ = runLaunchctl(["load", "-w", plistURL.path])
        } catch {
            // Ignore write failures; status is surfaced via UI on next apply.
        }
    }

    func uninstall() {
        _ = runLaunchctl(["unload", "-w", plistURL.path])
        try? FileManager.default.removeItem(at: plistURL)
    }

    private func runLaunchctl(_ args: [String]) -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = args
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return ProcessResult(exitCode: 1, output: "", error: error.localizedDescription)
        }

        let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let error = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return ProcessResult(exitCode: Int(process.terminationStatus), output: output, error: error)
    }
}
