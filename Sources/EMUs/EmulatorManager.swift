import Foundation

enum EmulatorPlatform: String, Codable {
    case android = "Android"
    case ios = "iOS"
}

enum EmulatorStatus: Equatable {
    case stopped
    case running(portOrId: String)
    case starting
    case stopping
}

struct EmulatorDevice: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let displayName: String
    let platform: EmulatorPlatform
    var status: EmulatorStatus
    let targetOrApi: String?
}

@MainActor
final class EmulatorManager: ObservableObject {
    @Published var emulators: [EmulatorDevice] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    
    private var refreshTimer: Timer?
    
    init() {
        startAutoRefresh()
    }
    
    deinit {
        refreshTimer?.invalidate()
    }
    
    func startAutoRefresh() {
        Task {
            await fetchEmulators()
        }
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.updateRunningStatuses()
            }
        }
    }
    
    // MARK: - Detect Paths (nonisolated)
    private nonisolated static func findEmulatorBinary() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let possiblePaths = [
            "\(home)/Library/Android/sdk/emulator/emulator",
            "/opt/homebrew/bin/emulator",
            "/usr/local/bin/emulator"
        ]
        
        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        
        let output = runShellCommand("which emulator").trimmingCharacters(in: .whitespacesAndNewlines)
        if !output.isEmpty && FileManager.default.fileExists(atPath: output) {
            return output
        }
        return nil
    }
    
    private nonisolated static func findAdbBinary() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let possiblePaths = [
            "\(home)/Library/Android/sdk/platform-tools/adb",
            "/opt/homebrew/bin/adb",
            "/usr/local/bin/adb"
        ]
        
        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        
        let output = runShellCommand("which adb").trimmingCharacters(in: .whitespacesAndNewlines)
        if !output.isEmpty && FileManager.default.fileExists(atPath: output) {
            return output
        }
        return nil
    }
    
    // MARK: - Fetching Emulators
    func fetchEmulators() async {
        isLoading = true
        errorMessage = nil
        
        var list: [EmulatorDevice] = []
        
        await Task.detached(priority: .userInitiated) {
            let emulatorBin = Self.findEmulatorBinary()
            let adbBin = Self.findAdbBinary()
            
            // 1. Android AVDs
            if let emulatorBin = emulatorBin {
                let avdOutput = Self.runProcess(executable: emulatorBin, arguments: ["-list-avds"])
                let avdNames = avdOutput
                    .components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                
                // Check running AVDs via adb
                let runningAvds = Self.getRunningAndroidAvds(adbPath: adbBin)
                
                for avd in avdNames {
                    let formattedName = avd.replacingOccurrences(of: "_", with: " ")
                    let runningInfo = runningAvds.first { $0.avdName == avd }
                    let status: EmulatorStatus
                    if let runningInfo = runningInfo {
                        status = .running(portOrId: runningInfo.serial)
                    } else {
                        status = .stopped
                    }
                    
                    list.append(EmulatorDevice(
                        name: avd,
                        displayName: formattedName,
                        platform: .android,
                        status: status,
                        targetOrApi: nil
                    ))
                }
            }
            
            // 2. iOS Simulators (if xcrun simctl exists)
            let simctlOutput = Self.runShellCommand("xcrun simctl list devices available -j 2>/dev/null")
            if let data = simctlOutput.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let devicesDict = json["devices"] as? [String: [[String: Any]]] {
                
                for (runtime, devices) in devicesDict where runtime.contains("iOS") {
                    let osVersion = runtime
                        .components(separatedBy: ".").last?
                        .replacingOccurrences(of: "iOS-", with: "iOS ")
                        .replacingOccurrences(of: "-", with: ".") ?? "iOS"
                    
                    for device in devices {
                        guard let name = device["name"] as? String,
                              let udid = device["udid"] as? String,
                              let state = device["state"] as? String,
                              let isAvailable = device["isAvailable"] as? Bool, isAvailable else { continue }
                        
                        // Filter out duplicates / Apple Watch / TV if any
                        if name.contains("Apple TV") || name.contains("Apple Watch") { continue }
                        
                        let status: EmulatorStatus = (state.lowercased() == "booted") ? .running(portOrId: udid) : .stopped
                        
                        list.append(EmulatorDevice(
                            name: udid,
                            displayName: name,
                            platform: .ios,
                            status: status,
                            targetOrApi: osVersion
                        ))
                    }
                }
            }
        }.value
        
        self.emulators = list
        self.isLoading = false
    }
    
    func updateRunningStatuses() async {
        guard !isLoading else { return }
        
        await Task.detached(priority: .background) {
            let adbBin = Self.findAdbBinary()
            let runningAndroid = Self.getRunningAndroidAvds(adbPath: adbBin)
            let bootedIosSims = Self.getBootedIosSimulators()
            
            await MainActor.run {
                for i in 0..<self.emulators.count {
                    let emu = self.emulators[i]
                    if emu.platform == .android {
                        if let matched = runningAndroid.first(where: { $0.avdName == emu.name }) {
                            self.emulators[i].status = .running(portOrId: matched.serial)
                        } else if case .running = self.emulators[i].status {
                            self.emulators[i].status = .stopped
                        }
                    } else if emu.platform == .ios {
                        if bootedIosSims.contains(emu.name) {
                            self.emulators[i].status = .running(portOrId: emu.name)
                        } else if case .running = self.emulators[i].status {
                            self.emulators[i].status = .stopped
                        }
                    }
                }
            }
        }.value
    }
    
    // MARK: - Actions
    func playEmulator(_ device: EmulatorDevice) {
        guard let index = emulators.firstIndex(where: { $0.id == device.id }) else { return }
        emulators[index].status = .starting
        
        Task.detached(priority: .userInitiated) {
            if device.platform == .android {
                if let emulatorBin = Self.findEmulatorBinary() {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: emulatorBin)
                    process.arguments = ["-avd", device.name]
                    process.standardOutput = FileHandle.nullDevice
                    process.standardError = FileHandle.nullDevice
                    try? process.run()
                }
            } else if device.platform == .ios {
                _ = Self.runShellCommand("xcrun simctl boot \(device.name)")
                _ = Self.runShellCommand("open -a Simulator")
            }
            
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await self.updateRunningStatuses()
        }
    }
    
    func coldBootEmulator(_ device: EmulatorDevice) {
        guard let index = emulators.firstIndex(where: { $0.id == device.id }) else { return }
        emulators[index].status = .starting
        
        Task.detached(priority: .userInitiated) {
            if device.platform == .android {
                let adbBin = Self.findAdbBinary()
                if case .running(let serial) = device.status, let adb = adbBin {
                    _ = Self.runProcess(executable: adb, arguments: ["-s", serial, "emu", "kill"])
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                }
                
                if let emulatorBin = Self.findEmulatorBinary() {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: emulatorBin)
                    process.arguments = ["-avd", device.name, "-no-snapshot-load"]
                    process.standardOutput = FileHandle.nullDevice
                    process.standardError = FileHandle.nullDevice
                    try? process.run()
                }
            } else if device.platform == .ios {
                _ = Self.runShellCommand("xcrun simctl shutdown \(device.name)")
                try? await Task.sleep(nanoseconds: 500_000_000)
                _ = Self.runShellCommand("xcrun simctl boot \(device.name)")
                _ = Self.runShellCommand("open -a Simulator")
            }
            
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await self.updateRunningStatuses()
        }
    }
    
    func stopEmulator(_ device: EmulatorDevice) {
        guard let index = emulators.firstIndex(where: { $0.id == device.id }) else { return }
        emulators[index].status = .stopping
        
        Task.detached(priority: .userInitiated) {
            if device.platform == .android {
                if let adbBin = Self.findAdbBinary() {
                    if case .running(let serial) = device.status {
                        _ = Self.runProcess(executable: adbBin, arguments: ["-s", serial, "emu", "kill"])
                    } else {
                        let running = Self.getRunningAndroidAvds(adbPath: adbBin)
                        if let matched = running.first(where: { $0.avdName == device.name }) {
                            _ = Self.runProcess(executable: adbBin, arguments: ["-s", matched.serial, "emu", "kill"])
                        }
                    }
                }
            } else if device.platform == .ios {
                _ = Self.runShellCommand("xcrun simctl shutdown \(device.name)")
            }
            
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await self.updateRunningStatuses()
        }
    }
    
    // MARK: - Helper Methods
    private nonisolated static func getRunningAndroidAvds(adbPath: String?) -> [(serial: String, avdName: String)] {
        guard let adb = adbPath else { return [] }
        let devicesOutput = runProcess(executable: adb, arguments: ["devices"])
        let lines = devicesOutput.components(separatedBy: .newlines)
        var results: [(serial: String, avdName: String)] = []
        
        for line in lines {
            let parts = line.split(separator: "\t")
            if parts.count >= 2, parts[1].trimmingCharacters(in: .whitespaces) == "device" {
                let serial = String(parts[0]).trimmingCharacters(in: .whitespaces)
                if serial.starts(with: "emulator-") {
                    let avdNameOutput = runProcess(executable: adb, arguments: ["-s", serial, "emu", "avd", "name"])
                    let avdName = avdNameOutput
                        .components(separatedBy: .newlines)
                        .first?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if !avdName.isEmpty && avdName != "OK" {
                        results.append((serial: serial, avdName: avdName))
                    }
                }
            }
        }
        return results
    }
    
    private nonisolated static func getBootedIosSimulators() -> Set<String> {
        let output = runShellCommand("xcrun simctl list devices | grep '(Booted)'")
        let lines = output.components(separatedBy: .newlines)
        var booted = Set<String>()
        for line in lines {
            let components = line.components(separatedBy: "(")
            if components.count >= 2 {
                let uuidPart = components[1].components(separatedBy: ")").first ?? ""
                if uuidPart.count == 36 {
                    booted.insert(uuidPart)
                }
            }
        }
        return booted
    }
    
    private nonisolated static func runShellCommand(_ command: String) -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }
    
    private nonisolated static func runProcess(executable: String, arguments: [String]) -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }
}
