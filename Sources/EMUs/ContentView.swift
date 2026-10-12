import SwiftUI

enum EmulatorTab: String, CaseIterable, Identifiable {
    case android = "Android"
    case ios = "iOS"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .android: return "cube.fill"
        case .ios: return "apple.logo"
        }
    }
}

struct ContentView: View {
    @StateObject private var manager = EmulatorManager()
    @State private var selectedTab: EmulatorTab = .android
    
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
            // Header bar
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "iphone.gen3")
                        .foregroundColor(.accentColor)
                        .font(.system(size: 16, weight: .bold))
                    Text("Emulators")
                        .font(.system(size: 15, weight: .bold))
                }
                
                Spacer()
                
                // Refresh button
                Button(action: {
                    Task {
                        await manager.fetchEmulators()
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Refresh")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .help("Refresh emulator list")
                .disabled(manager.isLoading)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)
            
            // Tab Selector Segment
            HStack(spacing: 8) {
                ForEach(EmulatorTab.allCases) { tab in
                    let count = (tab == .android) ? androidDevices.count : iosDevices.count
                    let isSelected = selectedTab == tab
                    
                    Button(action: {
                        selectedTab = tab
                    }) {
                        HStack(spacing: 7) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 13, weight: .semibold))
                            Text(tab.rawValue)
                                .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                            
                            // Badge with count
                            if !manager.isLoading {
                                Text("\(count)")
                                    .font(.system(size: 11, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        Capsule()
                                            .fill(isSelected ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.15))
                                    )
                                    .foregroundColor(isSelected ? .accentColor : .secondary)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(isSelected ? Color(nsColor: .controlBackgroundColor) : Color.clear)
                                .shadow(color: isSelected ? Color.black.opacity(0.12) : Color.clear, radius: 2, x: 0, y: 1)
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
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            
            Divider()
            
            // Content Body with full reliable scrollable area
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 10) {
                    if manager.isLoading && manager.emulators.isEmpty {
                        // Loader state
                        VStack(spacing: 14) {
                            ProgressView()
                                .controlSize(.regular)
                            Text("Detecting \(selectedTab.rawValue) emulators...")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 50)
                    } else if currentList.isEmpty {
                        // Empty state for this tab
                        VStack(spacing: 10) {
                            Image(systemName: selectedTab == .android ? "cube.fill" : "apple.logo")
                                .font(.system(size: 32))
                                .foregroundColor(.secondary.opacity(0.6))
                                .padding(.bottom, 2)
                            Text("No \(selectedTab.rawValue) Devices Found")
                                .font(.system(size: 14, weight: .semibold))
                            Text(selectedTab == .android ?
                                 "No Android Virtual Devices (AVDs) found in Android SDK." :
                                 "No available iOS Simulators detected in Xcode.")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 28)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else {
                        // Emulators List
                        ForEach(currentList) { device in
                            EmulatorRowView(device: device, manager: manager)
                        }
                    }
                }
                .padding(14)
            }
            
            Divider()
            
            // Footer: Count & Quit
            HStack {
                if manager.isLoading {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text("Scanning...")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                } else {
                    let runningCount = currentList.filter {
                        if case .running = $0.status { return true }
                        return false
                    }.count
                    
                    Text("\(currentList.count) \(selectedTab.rawValue) device\(currentList.count == 1 ? "" : "s") (\(runningCount) active)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: {
                    NSApplication.shared.terminate(nil)
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "power")
                        Text("Quit")
                    }
                    .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
        }
        .frame(width: 440, height: 500)
    }
}

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
            // Title & Status badge
            HStack(spacing: 10) {
                // Platform Icon
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
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    
                    if let target = device.targetOrApi {
                        Text(target)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // Status Indicator
                statusBadge
            }
            
            // Action Buttons: Play, Stop, Cold Boot
            HStack(spacing: 8) {
                // Play Button
                Button(action: {
                    manager.playEmulator(device)
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "play.fill")
                        Text("Play")
                    }
                    .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .disabled(isRunning || isOperating)
                
                // Stop Button
                Button(action: {
                    manager.stopEmulator(device)
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "stop.fill")
                        Text("Stop")
                    }
                    .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .tint(.red)
                .disabled(!isRunning || isOperating)
                
                // Cold Boot Button
                Button(action: {
                    manager.coldBootEmulator(device)
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Cold Boot")
                    }
                    .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
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
            HStack(spacing: 5) {
                Circle().fill(Color.green).frame(width: 7, height: 7)
                Text("Running")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.green)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.green.opacity(0.14))
            .cornerRadius(7)
            
        case .stopped:
            HStack(spacing: 5) {
                Circle().fill(Color.secondary).frame(width: 7, height: 7)
                Text("Stopped")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(7)
            
        case .starting:
            HStack(spacing: 5) {
                ProgressView().controlSize(.mini)
                Text("Starting...")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.orange)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.orange.opacity(0.14))
            .cornerRadius(7)
            
        case .stopping:
            HStack(spacing: 5) {
                ProgressView().controlSize(.mini)
                Text("Stopping...")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.red)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.red.opacity(0.14))
            .cornerRadius(7)
        }
    }
}
