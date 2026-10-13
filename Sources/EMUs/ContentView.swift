import SwiftUI

// MARK: - Navigation
enum SidebarItem: String, CaseIterable, Identifiable {
    case emulator = "Emulator"
    case wireless = "Wireless"
    case tunnel   = "Tunnel"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .emulator: return "iphone.gen3"
        case .wireless: return "wifi"
        case .tunnel:   return "arrow.triangle.2.circlepath"
        }
    }
}

enum DeviceTab: String, CaseIterable, Identifiable {
    case android = "Android"
    case ios     = "iOS"
    var id: String { rawValue }
    var icon: String { self == .android ? "cube.fill" : "apple.logo" }
}

// MARK: - ContentView
struct ContentView: View {
    @StateObject private var manager = EmulatorManager()
    @State private var selectedSidebar: SidebarItem = .emulator

    var body: some View {
        HStack(spacing: 0) {
            // ── Left sidebar ──────────────────────────────────────────
            SidebarView(selected: $selectedSidebar)

            Divider()

            // ── Right panel ───────────────────────────────────────────
            Group {
                switch selectedSidebar {
                case .emulator:
                    EmulatorPanel(manager: manager)
                case .wireless:
                    WirelessPanel(manager: manager)
                case .tunnel:
                    TunnelPanel(manager: manager)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 500, height: 520)
    }
}

// MARK: - Sidebar
struct SidebarView: View {
    @Binding var selected: SidebarItem

    var body: some View {
        VStack(spacing: 4) {
            ForEach(SidebarItem.allCases) { item in
                SidebarButton(item: item, isSelected: selected == item) {
                    selected = item
                }
            }
            Spacer()
        }
        .padding(.top, 14)
        .padding(.horizontal, 8)
        .frame(width: 110)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct SidebarButton: View {
    let item: SidebarItem
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: item.icon)
                    .font(.system(size: 18, weight: isSelected ? .semibold : .regular))
                Text(item.rawValue)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            )
            .foregroundColor(isSelected ? .accentColor : .secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Shared Tab Bar
struct PlatformTabBar: View {
    @Binding var selectedTab: DeviceTab
    let androidCount: Int?
    let iosCount: Int?
    let isLoading: Bool

    var body: some View {
        HStack(spacing: 8) {
            ForEach(DeviceTab.allCases) { tab in
                let count = tab == .android ? androidCount : iosCount
                let isSelected = selectedTab == tab
                Button(action: { selectedTab = tab }) {
                    HStack(spacing: 6) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 12, weight: .semibold))
                        Text(tab.rawValue)
                            .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                        if !isLoading, let count {
                            Text("\(count)")
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(isSelected ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.15))
                                )
                                .foregroundColor(isSelected ? .accentColor : .secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(isSelected ? Color(nsColor: .controlBackgroundColor) : Color.clear)
                            .shadow(color: isSelected ? Color.black.opacity(0.1) : .clear, radius: 2, x: 0, y: 1)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundColor(isSelected ? .primary : .secondary)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .separatorColor).opacity(0.18))
        )
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }
}

// MARK: - Panel Header
struct PanelHeader: View {
    let title: String
    let icon: String
    let isLoading: Bool
    let onRefresh: () -> Void

    var body: some View {
        HStack {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .foregroundColor(.accentColor)
                    .font(.system(size: 14, weight: .bold))
                Text(title)
                    .font(.system(size: 14, weight: .bold))
            }
            Spacer()
            Button(action: onRefresh) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Refresh")
                        .font(.system(size: 10, weight: .medium))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            .disabled(isLoading)
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }
}

// MARK: - Emulator Panel
struct EmulatorPanel: View {
    @ObservedObject var manager: EmulatorManager
    @State private var selectedTab: DeviceTab = .android

    private var androidDevices: [EmulatorDevice] {
        manager.emulators.filter { $0.platform == .android }
    }
    private var iosDevices: [EmulatorDevice] {
        manager.emulators.filter { $0.platform == .ios }
    }
    private var currentList: [EmulatorDevice] {
        selectedTab == .android ? androidDevices : iosDevices
    }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "Emulator", icon: "iphone.gen3", isLoading: manager.isLoading) {
                Task { await manager.fetchEmulators() }
            }

            PlatformTabBar(
                selectedTab: $selectedTab,
                androidCount: androidDevices.count,
                iosCount: iosDevices.count,
                isLoading: manager.isLoading
            )

            Divider()

            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 10) {
                    if manager.isLoading && manager.emulators.isEmpty {
                        loadingState
                    } else if currentList.isEmpty {
                        emptyState
                    } else {
                        ForEach(currentList) { device in
                            EmulatorRowView(device: device, manager: manager)
                        }
                    }
                }
                .padding(12)
            }

            Divider()
            footerBar
        }
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView().controlSize(.regular)
            Text("Detecting \(selectedTab.rawValue) emulators...")
                .font(.system(size: 12)).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 50)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: selectedTab == .android ? "cube.fill" : "apple.logo")
                .font(.system(size: 30)).foregroundColor(.secondary.opacity(0.5))
            Text("No \(selectedTab.rawValue) Devices Found")
                .font(.system(size: 13, weight: .semibold))
            Text(selectedTab == .android
                 ? "No AVDs found in Android SDK."
                 : "No iOS Simulators found in Xcode.")
                .font(.system(size: 11)).foregroundColor(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40)
    }

    private var footerBar: some View {
        HStack {
            if manager.isLoading {
                HStack(spacing: 5) {
                    ProgressView().controlSize(.mini)
                    Text("Scanning...").font(.system(size: 11)).foregroundColor(.secondary)
                }
            } else {
                let running = currentList.filter { if case .running = $0.status { return true }; return false }.count
                Text("\(currentList.count) device\(currentList.count == 1 ? "" : "s") (\(running) active)")
                    .font(.system(size: 11)).foregroundColor(.secondary)
            }
            Spacer()
            Button(action: { NSApplication.shared.terminate(nil) }) {
                HStack(spacing: 4) {
                    Image(systemName: "power")
                    Text("Quit")
                }
                .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.bordered).controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
    }
}

// MARK: - Wireless Panel
struct WirelessPanel: View {
    @ObservedObject var manager: EmulatorManager
    @State private var selectedTab: DeviceTab = .android

    private var androidWireless: [WirelessDevice] {
        manager.wirelessDevices.filter { $0.platform == .android }
    }
    private var iosWireless: [WirelessDevice] {
        manager.wirelessDevices.filter { $0.platform == .ios }
    }
    private var currentList: [WirelessDevice] {
        selectedTab == .android ? androidWireless : iosWireless
    }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "Wireless", icon: "wifi", isLoading: manager.isLoadingWireless) {
                Task { await manager.fetchWirelessDevices() }
            }

            PlatformTabBar(
                selectedTab: $selectedTab,
                androidCount: androidWireless.count,
                iosCount: iosWireless.count,
                isLoading: manager.isLoadingWireless
            )

            Divider()

            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 10) {
                    if manager.isLoadingWireless && manager.wirelessDevices.isEmpty {
                        VStack(spacing: 12) {
                            ProgressView().controlSize(.regular)
                            Text("Scanning for wireless devices...")
                                .font(.system(size: 12)).foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 50)
                    } else if currentList.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: selectedTab == .android ? "cube.fill" : "apple.logo")
                                .font(.system(size: 30)).foregroundColor(.secondary.opacity(0.5))
                            Text("No Wireless \(selectedTab.rawValue) Devices")
                                .font(.system(size: 13, weight: .semibold))
                            Text(selectedTab == .android
                                 ? "No Android devices connected via wireless ADB."
                                 : "No iOS devices paired wirelessly.")
                                .font(.system(size: 11)).foregroundColor(.secondary)
                                .multilineTextAlignment(.center).padding(.horizontal, 20)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 40)
                    } else {
                        ForEach(currentList) { device in
                            WirelessDeviceRow(device: device)
                        }
                    }
                }
                .padding(12)
            }

            Divider()
            HStack {
                Text("\(currentList.count) wireless device\(currentList.count == 1 ? "" : "s")")
                    .font(.system(size: 11)).foregroundColor(.secondary)
                Spacer()
                Button(action: { NSApplication.shared.terminate(nil) }) {
                    HStack(spacing: 4) { Image(systemName: "power"); Text("Quit") }
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered).controlSize(.small)
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
        }
        .onAppear {
            if manager.wirelessDevices.isEmpty {
                Task { await manager.fetchWirelessDevices() }
            }
        }
    }
}

struct WirelessDeviceRow: View {
    let device: WirelessDevice

    var connectionColor: Color {
        switch device.connectionState {
        case .connected:    return .green
        case .disconnected: return .orange
        case .unavailable:  return .secondary
        }
    }

    var connectionLabel: String {
        switch device.connectionState {
        case .connected:    return "Connected"
        case .disconnected: return "Disconnected"
        case .unavailable:  return "Unavailable"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            // Platform icon
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(device.platform == .android ? Color.green.opacity(0.12) : Color.blue.opacity(0.1))
                    .frame(width: 36, height: 36)
                Image(systemName: device.platform == .android ? "cube.fill" : "apple.logo")
                    .font(.system(size: 16))
                    .foregroundColor(device.platform == .android ? .green : .primary)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(device.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                HStack(spacing: 8) {
                    if let model = device.model {
                        Text(model)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    if let osVersion = device.osVersion {
                        Text(osVersion)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                if let serial = device.serial {
                    Text(serial)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.7))
                        .lineLimit(1)
                }
            }

            Spacer()

            // Connection state badge
            HStack(spacing: 4) {
                Circle()
                    .fill(connectionColor)
                    .frame(width: 6, height: 6)
                Text(connectionLabel)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(connectionColor)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(connectionColor.opacity(0.12))
            .cornerRadius(6)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.85))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    device.connectionState == .connected ? Color.green.opacity(0.35) : Color.gray.opacity(0.18),
                    lineWidth: 1
                )
        )
    }
}

// MARK: - Tunnel Panel
struct TunnelPanel: View {
    @ObservedObject var manager: EmulatorManager
    @State private var hostPort: String = "8081"
    @State private var devicePort: String = "8081"
    @State private var lastResult: TunnelResult? = nil
    @State private var isRunning: Bool = false

    enum TunnelResult {
        case success(String)
        case failure(String)
    }

    private var commandPreview: String {
        let h = hostPort.isEmpty ? "<host_port>" : hostPort
        let d = devicePort.isEmpty ? "<device_port>" : devicePort
        return "adb reverse tcp:\(d) tcp:\(h)"
    }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "Tunnel", icon: "arrow.triangle.2.circlepath", isLoading: false) {}

            Divider()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {

                    // Description
                    Text("Reverse tunnel lets your Android device reach a server running on your Mac.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    // Port inputs
                    VStack(spacing: 12) {
                        portRow(
                            label: "Host Port",
                            subtitle: "Port on your Mac",
                            icon: "desktopcomputer",
                            binding: $hostPort
                        )
                        portRow(
                            label: "Device Port",
                            subtitle: "Port on Android device",
                            icon: "iphone",
                            binding: $devicePort
                        )
                    }

                    // Command preview
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Command Preview")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)

                        HStack {
                            Text(commandPreview)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(.primary)
                                .lineLimit(1)
                            Spacer()
                            Button(action: {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(commandPreview, forType: .string)
                            }) {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 11))
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.secondary)
                            .help("Copy command")
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                    }

                    // Run button
                    Button(action: runTunnel) {
                        HStack(spacing: 6) {
                            if isRunning {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "play.fill")
                            }
                            Text(isRunning ? "Running..." : "Run Reverse Tunnel")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(hostPort.isEmpty || devicePort.isEmpty || isRunning)

                    // Result banner
                    if let result = lastResult {
                        HStack(spacing: 8) {
                            switch result {
                            case .success(let msg):
                                Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                                Text(msg).font(.system(size: 12)).foregroundColor(.green)
                            case .failure(let msg):
                                Image(systemName: "xmark.circle.fill").foregroundColor(.red)
                                Text(msg).font(.system(size: 12)).foregroundColor(.red)
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill({
                                    if case .success = result { return Color.green.opacity(0.1) }
                                    return Color.red.opacity(0.1)
                                }())
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke({
                                    if case .success = result { return Color.green.opacity(0.3) }
                                    return Color.red.opacity(0.3)
                                }(), lineWidth: 1)
                        )
                    }
                }
                .padding(16)
            }

            Divider()
            HStack {
                Spacer()
                Button(action: { NSApplication.shared.terminate(nil) }) {
                    HStack(spacing: 4) { Image(systemName: "power"); Text("Quit") }
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered).controlSize(.small)
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
        }
    }

    @ViewBuilder
    private func portRow(label: String, subtitle: String, icon: String, binding: Binding<String>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            Spacer()

            TextField("8081", text: binding)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13, design: .monospaced))
                .frame(width: 72)
                .multilineTextAlignment(.center)
                .onChange(of: binding.wrappedValue) { newVal in
                    // Allow only digits, max 5 chars
                    let filtered = String(newVal.filter(\.isNumber).prefix(5))
                    if filtered != newVal { binding.wrappedValue = filtered }
                    lastResult = nil
                }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.8))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
        )
    }

    private func runTunnel() {
        guard !hostPort.isEmpty, !devicePort.isEmpty else { return }
        isRunning = true
        lastResult = nil
        Task {
            let result = await manager.runAdbReverse(devicePort: devicePort, hostPort: hostPort)
            await MainActor.run {
                isRunning = false
                if result.success {
                    lastResult = .success("Tunnel active: device:\(devicePort) → Mac:\(hostPort)")
                } else {
                    lastResult = .failure(result.error ?? "adb reverse failed")
                }
            }
        }
    }
}

// MARK: - Emulator Row (unchanged)
struct EmulatorRowView: View {
    let device: EmulatorDevice
    @ObservedObject var manager: EmulatorManager

    var isRunning: Bool {
        if case .running = device.status { return true }
        return false
    }
    var isOperating: Bool {
        device.status == .starting || device.status == .stopping
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(device.platform == .android ? Color.green.opacity(0.15) : Color.primary.opacity(0.08))
                        .frame(width: 32, height: 32)
                    Image(systemName: device.platform == .android ? "cube.fill" : "apple.logo")
                        .foregroundColor(device.platform == .android ? .green : .primary)
                        .font(.system(size: 15))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(device.displayName)
                        .font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    if let target = device.targetOrApi {
                        Text(target).font(.system(size: 11)).foregroundColor(.secondary)
                    }
                }
                Spacer()
                statusBadge
            }

            HStack(spacing: 8) {
                Button(action: { manager.playEmulator(device) }) {
                    HStack(spacing: 4) {
                        Image(systemName: "play.fill"); Text("Play")
                    }
                    .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered).controlSize(.regular)
                .disabled(isRunning || isOperating)

                Button(action: { manager.stopEmulator(device) }) {
                    HStack(spacing: 4) {
                        Image(systemName: "stop.fill"); Text("Stop")
                    }
                    .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered).controlSize(.regular).tint(.red)
                .disabled(!isRunning || isOperating)

                Button(action: { manager.coldBootEmulator(device) }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.counterclockwise"); Text("Cold Boot")
                    }
                    .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered).controlSize(.regular)
                .disabled(isOperating)

                Spacer()
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.85))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isRunning ? Color.green.opacity(0.4) : Color.gray.opacity(0.18), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch device.status {
        case .running:
            badge(dot: .green, label: "Running", text: .green, bg: Color.green.opacity(0.14))
        case .stopped:
            badge(dot: .secondary, label: "Stopped", text: .secondary, bg: Color.secondary.opacity(0.1))
        case .starting:
            HStack(spacing: 5) {
                ProgressView().controlSize(.mini)
                Text("Starting...").font(.system(size: 11, weight: .medium)).foregroundColor(.orange)
            }
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Color.orange.opacity(0.14)).cornerRadius(7)
        case .stopping:
            HStack(spacing: 5) {
                ProgressView().controlSize(.mini)
                Text("Stopping...").font(.system(size: 11, weight: .medium)).foregroundColor(.red)
            }
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Color.red.opacity(0.14)).cornerRadius(7)
        }
    }

    private func badge(dot: Color, label: String, text: Color, bg: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(dot).frame(width: 7, height: 7)
            Text(label).font(.system(size: 11, weight: .semibold)).foregroundColor(text)
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(bg).cornerRadius(7)
    }
}
