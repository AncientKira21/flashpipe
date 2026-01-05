//
//  FlashPipeApp.swift
//  FlashPipe
//
//  Created by Ancient Kira on 10/13/25.
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

#if os(macOS)
final class FlashPipeAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Quit the app when the last window is closed
        return true
    }
}
#endif

enum FlashAction {
    case recovery
    case logo
    case gsi
}

@main
struct FlashPipeApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(FlashPipeAppDelegate.self) private var appDelegate
    #endif

    init() {
        setenv("OS_ACTIVITY_MODE", "default", 1)
        print("[FlashPipeApp] init: App launching")
    }
    @StateObject private var nav = AppNavigation()
    @StateObject private var devices = ADBDevicesViewModel()
    @StateObject private var installState = FPInstallState(toolsReady: true)
    @State private var debugLogEnabled: Bool = true
    @State private var showSidebar: Bool = false
    @State private var showingFastbootPicker: Bool = false
    @State private var preselectedFastbootSerial: String? = nil
    @State private var pendingFlashAction: FlashAction? = nil
    @AppStorage("selectedLanguage") private var selectedLanguage = "en"

    private var isMacOS26OrNewer: Bool {
        #if os(macOS)
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return v.majorVersion >= 26
        #else
        return false
        #endif
    }
    
    var body: some Scene {
        WindowGroup {
            StartInstallViewCheck(showSidebar: $showSidebar)
                .environmentObject(nav)
                .environmentObject(installState)
                .environmentObject(devices)
                .onAppear {
                    print("[FlashPipeApp] WindowGroup onAppear")
                    Bundle.setLanguage(selectedLanguage)
                }
                .sheet(isPresented: $showingFastbootPicker) {
                    FastbootDevicePickerSheet(selectedSerial: $preselectedFastbootSerial) {
                        print("[FlashPipeApp] Fastboot selection confirmed; serial=\(String(describing: preselectedFastbootSerial)) action=\(String(describing: pendingFlashAction))")
                        // Dismiss and let Fastboot1View proceed with the selected serial and action
                        showingFastbootPicker = false
                        // Trigger navigation is already set to .fastboot
                        // Fastboot1View will pick up preselected serial and action via environment or global state
                        NotificationCenter.default.post(name: Notification.Name("FlashPipe_Fastboot_ApplySelection"), object: nil, userInfo: [
                            "serial": preselectedFastbootSerial as Any,
                            "action": {
                                switch pendingFlashAction {
                                case .recovery: return "recovery"
                                case .logo: return "logo"
                                case .gsi: return "gsi"
                                case .none: return ""
                                }
                            }()
                        ])
                    }
                    .onAppear {
                        print("[FlashPipeApp] Presenting FastbootDevicePickerSheet; pendingAction=\(String(describing: pendingFlashAction)) preselected=\(String(describing: preselectedFastbootSerial))")
                    }
                }
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button(action: {
                    print("[FlashPipeApp] Command: About selected")
                    // Navigate to Settings first, then request SettingsView to push About
                    nav.selection = .settings
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: Notification.Name("FlashPipe_Settings_ShowAbout"), object: nil)
                    }
                }) {
                    if isMacOS26OrNewer {
                        Label("About FlashPipe", systemImage: "info.circle")
                    } else {
                        Text("About FlashPipe")
                    }
                }
            }
            CommandGroup(after: .appSettings) {
                Button(action: { print("[FlashPipeApp] Command: Settings selected"); nav.selection = .settings }) {
                    if isMacOS26OrNewer {
                        Label("Settings…", systemImage: "gearshape")
                    } else {
                        Text("Settings…")
                    }
                }
                .keyboardShortcut(",", modifiers: [.command])
            }
            CommandMenu("Flash") {
                Button(action: {
                    print("[FlashPipeApp] Command: Flash Recovery chosen")
                    pendingFlashAction = .recovery
                    nav.selection = .fastboot
                    showingFastbootPicker = true
                }) {
                    Label("Recovery", systemImage: "wrench")
                }
                Button(action: {
                    print("[FlashPipeApp] Command: Flash Logo chosen")
                    pendingFlashAction = .logo
                    nav.selection = .fastboot
                    showingFastbootPicker = true
                }) {
                    Label("Logo", systemImage: "photo")
                }
                Button(action: {
                    print("[FlashPipeApp] Command: Flash GSI chosen")
                    pendingFlashAction = .gsi
                    nav.selection = .fastboot
                    showingFastbootPicker = true
                }) {
                    Label("GSI", systemImage: "square.stack.3d.up")
                }
                Divider()
                Button(action: { nav.selection = .flashRom }) {
                    if isMacOS26OrNewer {
                        Label("ROM", systemImage: "externaldrive")
                    } else {
                        Text("ROM")
                    }
                }
            }
            CommandMenu("Reboot") {

                // --- Section: ADB ---
                Text("ADB")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button(action: {
                    print("[FlashPipeApp] Command: ADB Normal Reboot")
                    pendingFlashAction = nil
                    nav.selection = .adbDevices
                    NotificationCenter.default.post(name: Notification.Name("FlashPipe_Reboot_Normal"), object: nil)
                }) {
                    if isMacOS26OrNewer {
                        Label("Normal Reboot", systemImage: "arrow.clockwise")
                    } else {
                        Text("Normal Reboot")
                    }
                }

                Button(action: {
                    print("[FlashPipeApp] Command: ADB Reboot to Fastboot")
                    pendingFlashAction = nil
                    nav.selection = .adbDevices
                    NotificationCenter.default.post(name: Notification.Name("FlashPipe_Reboot_Fastboot"), object: nil)
                }) {
                    if isMacOS26OrNewer {
                        Label("Fastboot", systemImage: "bolt")
                    } else {
                        Text("Fastboot")
                    }
                }

                Button(action: {
                    print("[FlashPipeApp] Command: ADB Reboot to Recovery")
                    pendingFlashAction = nil
                    nav.selection = .adbDevices
                    NotificationCenter.default.post(name: Notification.Name("FlashPipe_Reboot_Recovery"), object: nil)
                }) {
                    if isMacOS26OrNewer {
                        Label("Recovery", systemImage: "wrench")
                    } else {
                        Text("Recovery")
                    }
                }

                Button(action: {
                    print("[FlashPipeApp] Command: ADB Reboot to Download Mode")
                    pendingFlashAction = nil
                    nav.selection = .adbDevices
                    NotificationCenter.default.post(name: Notification.Name("FlashPipe_Reboot_DownloadMode"), object: nil)
                }) {
                    if isMacOS26OrNewer {
                        Label("Download Mode", systemImage: "arrow.down")
                    } else {
                        Text("Download Mode")
                    }
                }

                Divider()

                // --- Section: Fastboot ---
                Text("Fastboot")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button(action: {
                    print("[FlashPipeApp] Command: Fastboot Normal Reboot flow")
                    pendingFlashAction = nil
                    nav.selection = .fastboot
                    preselectedFastbootSerial = nil
                    showingFastbootPicker = true
                    // After sheet confirm, Fastboot1View will execute via notification with action "rebootNormal"
                    NotificationCenter.default.post(name: Notification.Name("FlashPipe_Fastboot_ApplySelection"), object: nil, userInfo: [
                        "serial": preselectedFastbootSerial as Any,
                        "action": "rebootNormal"
                    ])
                }) {
                    if isMacOS26OrNewer {
                        Label("Normal Reboot", systemImage: "arrow.clockwise")
                    } else {
                        Text("Normal Reboot")
                    }
                }

                Button(action: {
                    print("[FlashPipeApp] Command: Fastboot Reboot Bootloader flow")
                    pendingFlashAction = nil
                    nav.selection = .fastboot
                    preselectedFastbootSerial = nil
                    showingFastbootPicker = true
                    NotificationCenter.default.post(name: Notification.Name("FlashPipe_Fastboot_ApplySelection"), object: nil, userInfo: [
                        "serial": preselectedFastbootSerial as Any,
                        "action": "rebootBootloader"
                    ])
                }) {
                    if isMacOS26OrNewer {
                        Label("Fastboot", systemImage: "bolt")
                    } else {
                        Text("Fastboot")
                    }
                }

                Button(action: {
                    print("[FlashPipeApp] Command: Fastboot Reboot Fastbootd flow")
                    pendingFlashAction = nil
                    nav.selection = .fastboot
                    preselectedFastbootSerial = nil
                    showingFastbootPicker = true
                    NotificationCenter.default.post(name: Notification.Name("FlashPipe_Fastboot_ApplySelection"), object: nil, userInfo: [
                        "serial": preselectedFastbootSerial as Any,
                        "action": "rebootFastbootd"
                    ])
                }) {
                    if isMacOS26OrNewer {
                        Label("Fastbootd", systemImage: "bolt.fill")
                    } else {
                        Text("Fastbootd")
                    }
                }

                Button(action: {
                    print("[FlashPipeApp] Command: Fastboot Reboot Recovery flow")
                    pendingFlashAction = nil
                    nav.selection = .fastboot
                    preselectedFastbootSerial = nil
                    showingFastbootPicker = true
                    NotificationCenter.default.post(name: Notification.Name("FlashPipe_Fastboot_ApplySelection"), object: nil, userInfo: [
                        "serial": preselectedFastbootSerial as Any,
                        "action": "rebootRecovery"
                    ])
                }) {
                    if isMacOS26OrNewer {
                        Label("Recovery", systemImage: "wrench")
                    } else {
                        Text("Recovery")
                    }
                }
            }
        }
    }
}

private struct FastbootDevicePickerSheet: View {
    @StateObject private var vm = FastbootDevicesViewModel()
    @Binding var selectedSerial: String?
    var onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(alignment: .center, spacing: 16) {
            HStack(spacing: 8) {
                Spacer()
                Text("Select a fastboot device")
                    .font(.title2)
                Button {
                    // Refresh the fastboot devices list
                    vm.stopScanning()
                    vm.startScanning()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .help("Refresh devices")
                .keyboardShortcut("r", modifiers: [.command])
                Spacer()
            }
            .multilineTextAlignment(.center)
            .padding(.top, 20)
            
            if vm.devices.count <= 1 {
                // Auto-select single device
                if let single = vm.devices.first {
                    Text(single.displayName)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .onAppear { selectedSerial = single.serial }
                } else {
                    Text("No devices detected")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            } else {
                HStack { Spacer() }
                Picker("Device", selection: Binding<String?>(
                    get: { selectedSerial ?? vm.devices.first?.serial },
                    set: { selectedSerial = $0 }
                )) {
                    ForEach(vm.devices) { device in
                        Text(device.displayName).tag(device.serial as String?)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            
            VStack(alignment: .leading, spacing: 12) {
                Label("Fastboot Setup Instructions", systemImage: "info.circle")
                    .font(.subheadline)
                
                ScrollView {
                    Text(
                        """
                        To use Fastboot, ensure:
                        
                        1. Your device is in Fastboot mode:
                           • From Android: adb reboot bootloader
                           • Or manually: Power off → hold Volume Down + Power.
                        
                        2. Connect your device via USB.
                        
                        3. Click Refresh to detect the fastboot device.
                        
                        Fastboot mode is required for tasks such as flashing recovery, boot images, or preparing for ROM installation.
                        """
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 100)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(.controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                    )
            )
        }
        
        HStack(spacing: 12) {
            Button("Cancel") { dismiss() }
            Button("Continue") {
                if selectedSerial == nil { selectedSerial = vm.devices.first?.serial }
                onConfirm()
            }
            .buttonStyle(.borderedProminent)
            .disabled(vm.devices.isEmpty)
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
        .padding(.top, 4)
        .padding()
        .frame(minWidth: 340)
        .frame(maxWidth: .infinity, alignment: .center)
        .onAppear { vm.startScanning() }
        .onDisappear { vm.stopScanning() }
    }
}

