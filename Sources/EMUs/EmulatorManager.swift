import Foundation

enum EmulatorPlatform: String, Codable {
    case android = "Android"
    case ios = "iOS"
}

// MARK: - Wireless Device Model
enum WirelessConnectionState {
    case connected
    case disconnected
    case unavailable
}

struct WirelessDevice: Identifiable, Equatable {
    var id: String { serial ?? name }
    let name: String
    let platform: EmulatorPlatform
    let model: String?
    let osVersion: String?
    let serial: String?
    let connectionState: WirelessConnectionState

    static func == (lhs: WirelessDevice, rhs: WirelessDevice) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Tunnel Result
struct TunnelResult {
    let success: Bool
    let error: String?
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

    @Published var wirelessDevices: [WirelessDevice] = []
    @Published var isLoadingWireless: Bool = false
    
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
        let env = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var possiblePaths: [String] = []
        
        if let androidHome = env["ANDROID_HOME"], !androidHome.isEmpty {
            possiblePaths.append("\(androidHome)/emulator/emulator")
        }
        if let androidSdkRoot = env["ANDROID_SDK_ROOT"], !androidSdkRoot.isEmpty {
            possiblePaths.append("\(androidSdkRoot)/emulator/emulator")
        }
        
        possiblePaths.append(contentsOf: [
            "\(home)/Library/Android/sdk/emulator/emulator",
            "/opt/homebrew/bin/emulator",
            "/usr/local/bin/emulator"
        ])
        
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
        let env = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var possiblePaths: [String] = []
        
        if let androidHome = env["ANDROID_HOME"], !androidHome.isEmpty {
            possiblePaths.append("\(androidHome)/platform-tools/adb")
        }
        if let androidSdkRoot = env["ANDROID_SDK_ROOT"], !androidSdkRoot.isEmpty {
            possiblePaths.append("\(androidSdkRoot)/platform-tools/adb")
        }
        
        possiblePaths.append(contentsOf: [
            "\(home)/Library/Android/sdk/platform-tools/adb",
            "/opt/homebrew/bin/adb",
            "/usr/local/bin/adb"
        ])
        
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

    // MARK: - Wireless Devices
    func fetchWirelessDevices() async {
        isLoadingWireless = true
        var list: [WirelessDevice] = []

        await Task.detached(priority: .userInitiated) {
            // ── Android: adb devices -l, pick entries with _adb-tls-connect (wireless)
            // or plain IP:port entries (manual adb connect)
            let adbBin = Self.findAdbBinary()
            if let adb = adbBin {
                let output = Self.runProcess(executable: adb, arguments: ["devices", "-l"])
                let lines = output.components(separatedBy: .newlines)
                for line in lines {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty,
                          !trimmed.hasPrefix("List of devices"),
                          !trimmed.hasPrefix("emulator-") else { continue }

                    // Wireless = serial contains _adb-tls-connect OR matches IP:port pattern
                    let isWirelessTls  = trimmed.contains("_adb-tls-connect")
                    let isIpConnect    = trimmed.first?.isNumber == true && trimmed.contains(".")
                    guard isWirelessTls || isIpConnect else { continue }

                    let parts = trimmed.components(separatedBy: .whitespaces)
                    guard let serial = parts.first,
                          parts.contains("device") else { continue }

                    // Read device props
                    let model   = Self.runProcess(executable: adb, arguments: ["-s", serial, "shell", "getprop", "ro.product.model"])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let brand   = Self.runProcess(executable: adb, arguments: ["-s", serial, "shell", "getprop", "ro.product.brand"])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let android = Self.runProcess(executable: adb, arguments: ["-s", serial, "shell", "getprop", "ro.build.version.release"])
                        .trimmingCharacters(in: .whitespacesAndNewlines)

                    let displayName = model.isEmpty ? serial : model
                    let fullModel   = brand.isEmpty ? nil : "\(brand.capitalized) \(model)"
                    let osString    = android.isEmpty ? nil : "Android \(android)"

                    list.append(WirelessDevice(
                        name: displayName,
                        platform: .android,
                        model: fullModel,
                        osVersion: osString,
                        serial: serial,
                        connectionState: .connected
                    ))
                }
            }

            // ── iOS: xcrun devicectl list devices --json-output
            let tmpFile = FileManager.default.temporaryDirectory
                .appendingPathComponent("emu_devicectl_\(UUID().uuidString).json").path
            _ = Self.runShellCommand("xcrun devicectl list devices --json-output \(tmpFile) 2>/dev/null")

            if let data = try? Data(contentsOf: URL(fileURLWithPath: tmpFile)),
               let json  = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let result = json["result"] as? [String: Any],
               let devices = result["devices"] as? [[String: Any]] {

                for device in devices {
                    let cp  = device["connectionProperties"] as? [String: Any] ?? [:]
                    let dp  = device["deviceProperties"]    as? [String: Any] ?? [:]
                    let hp  = device["hardwareProperties"]  as? [String: Any] ?? [:]

                    guard let platform = hp["platform"] as? String, platform == "iOS" else { continue }

                    let name        = dp["name"]          as? String ?? "Unknown Device"
                    let marketing   = hp["marketingName"] as? String
                    let osVersion   = dp["osVersionNumber"] as? String
                    let udid        = hp["udid"]          as? String
                    let tunnelState = cp["tunnelState"]   as? String ?? "unavailable"

                    let connState: WirelessConnectionState
                    switch tunnelState.lowercased() {
                    case "connected":    connState = .connected
                    case "disconnected": connState = .disconnected
                    default:             connState = .unavailable
                    }

                    list.append(WirelessDevice(
                        name: name,
                        platform: .ios,
                        model: marketing,
                        osVersion: osVersion.map { "iOS \($0)" },
                        serial: udid,
                        connectionState: connState
                    ))
                }
            }
            try? FileManager.default.removeItem(atPath: tmpFile)
        }.value

        self.wirelessDevices = list
        self.isLoadingWireless = false
    }

    // MARK: - ADB Reverse Tunnel
    func runAdbReverse(devicePort: String, hostPort: String) async -> TunnelResult {
        return await Task.detached(priority: .userInitiated) {
            guard let adb = Self.findAdbBinary() else {
                return TunnelResult(success: false, error: "adb not found")
            }
            let process = Process()
            let outPipe  = Pipe()
            let errPipe  = Pipe()
            process.executableURL = URL(fileURLWithPath: adb)
            process.arguments    = ["reverse", "tcp:\(devicePort)", "tcp:\(hostPort)"]
            process.standardOutput = outPipe
            process.standardError  = errPipe
            do {
                try process.run()
                process.waitUntilExit()
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                let errStr  = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if process.terminationStatus == 0 {
                    return TunnelResult(success: true, error: nil)
                } else {
                    return TunnelResult(success: false, error: errStr.isEmpty ? "Exit code \(process.terminationStatus)" : errStr)
                }
            } catch {
                return TunnelResult(success: false, error: error.localizedDescription)
            }
        }.value
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
