//
//  UnlockView.swift
//  FlashPipe
//
//  Created by Ancient Kira on 11/30/25.
//

import SwiftUI
import Combine
import UniformTypeIdentifiers

struct UnlockView: View {
//    @EnvironmentObject private var nav: AppNavigation
    @StateObject private var viewModel = FastbootDevicesViewModel()

    @State private var isSearching = false

    @State private var showUnlockConfirm = false
    @State private var showLockConfirm = false

    private var isMacOS26OrNewer: Bool {
        #if os(macOS)
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26
        #else
        false
        #endif
    }

    var body: some View {
        VStack(spacing: 24) {
            contentView
        }
        .padding()
        .frame(minWidth: 420, minHeight: 420)
        .navigationTitle("Unlock Bootloader")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    viewModel.startScanning()
                    startSearchWindow()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
        .onAppear {
            viewModel.startScanning()
            startSearchWindow()
        }
        .onDisappear {
            viewModel.stopScanning()
        }
        .alert("Unlock Bootloader?", isPresented: $showUnlockConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Continue") { performUnlock() }
        } message: {
            Text("""
Are you sure you want to unlock the bootloader?

• This may wipe all user data.
• You will void your warranty.
• BACK UP before continuing.

After unlocking, you can install custom ROMs or GSIs.

Continue?
""")
        }
        .alert("Lock Bootloader?", isPresented: $showLockConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Continue") { performLock() }
        } message: {
            Text("""
Are you sure you want to lock the bootloader?

• This may wipe data again.
• Your device will bootloop unless it is completely stock (no root).

Continue?
""")
        }
    }

    // MARK: - Main Content

    private var contentView: some View {
        VStack(spacing: 30) {
            Group {
                if viewModel.devices.isEmpty {
                    emptyStateView
                } else {
                    deviceFoundView
                }
            }
            .frame(maxWidth: 350)

            FastbootInstructionsView()
                .frame(maxWidth: 450)
        }
        .frame(maxWidth: .infinity)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                if isSearching {
                    HStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Searching for devices…")
                            .font(.headline)
                    }
                    .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 10) {
                        Image(systemName: "nosign")
                        Text("No devices found.")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                }

                Text("Please ensure your Android device is connected and in fastboot mode.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 10)
            
            Button {} label: {
                Text("Continue")
                    .frame(minWidth: 120)
            }
            .buttonStyle(.borderedProminent)
            .disabled(true)
        }
        .padding(.vertical, 20)
    }

    private var deviceFoundView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(viewModel.devices.count > 1 ? "Devices Detected" : "Device Detected")
                .font(.title3)
                .bold()
            
            if viewModel.devices.count == 1 {
                let single = viewModel.devices.first!
                Text(single.displayName)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .onAppear {
                        viewModel.selectedSerial = single.serial
                    }
            } else if viewModel.devices.count > 1 {
                Picker("Select Device", selection: Binding<String?>(
                    get: { viewModel.selectedSerial },
                    set: { viewModel.selectedSerial = $0 }
                )) {
                    ForEach(viewModel.devices) { device in
                        Text(device.displayName).tag(device.serial as String?)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: viewModel.selectedSerial) {
                    // No-op: keep to trigger view updates if needed
                }
                .onAppear {
                    if let first = viewModel.devices.first {
                        viewModel.selectedSerial = first.serial
                    }
                }
            }
            
            HStack {
                Text("Selected:")
                if viewModel.devices.count == 1, let single = viewModel.devices.first {
                    Text(single.displayName)
                        .foregroundStyle(.primary)
                } else if let selected = viewModel.selectedSerial,
                          let dev = viewModel.devices.first(where: { $0.serial == selected }) {
                    Text(dev.displayName)
                        .foregroundStyle(.primary)
                } else {
                    Text("No device selected")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.subheadline)
            
            Spacer().frame(height: 10)
            
            // Brand check
//            if let dev = selectedOrFirstDevice(),
//               dev.displayName.localizedCaseInsensitiveContains("pixel") {
//                Label("Pixel devices are fully supported for bootloader unlocking.", systemImage: "checkmark.seal")
//                    .foregroundStyle(.green)
//            }

            // Buttons
            Menu {
                Button {
                    showUnlockConfirm = true
                } label: {
                    if isMacOS26OrNewer {
                        Label("Unlock Bootloader", systemImage: "lock.open")
                    } else {
                        Text("Unlock Bootloader")
                    }
                }
                Button {
                    showLockConfirm = true
                } label: {
                    if isMacOS26OrNewer {
                        Label("Lock Bootloader", systemImage: "lock")
                    } else {
                        Text("Lock Bootloader")
                    }
                }
            } label: {
                Label("Bootloader…", systemImage: "gearshape")
            }
            .disabled(!isSelectedDeviceSupported())

            Button {
                if let targetDevice = selectedOrFirstDevice() {
                    Task {
                        _ = runFastboot(serial: targetDevice.serial, args: ["reboot"]) 
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        viewModel.startScanning()
                        startSearchWindow()
                    }
                }
            } label: {
                Label("Reboot Device", systemImage: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(.bordered)

        }
    }

    // MARK: - Bootloader Actions

    private func performUnlock() {
        guard let serial = viewModel.selectedSerial else { return }
        _ = runFastboot(serial: serial, args: ["flashing", "unlock"])
    }

    private func performLock() {
        guard let serial = viewModel.selectedSerial else { return }
        _ = runFastboot(serial: serial, args: ["flashing", "lock"])
    }

    // MARK: - Helpers

    private func selectedOrFirstDevice() -> FastbootDevice? {
        if let s = viewModel.selectedSerial {
            return viewModel.devices.first(where: { $0.serial == s })
        }
        return viewModel.devices.first
    }

    private func startSearchWindow() {
        isSearching = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
            if viewModel.devices.isEmpty { isSearching = false }
        }
    }
    private func isSelectedDeviceSupported() -> Bool {
        guard let dev = selectedOrFirstDevice() else { return false }
        return dev.displayName.localizedCaseInsensitiveContains("pixel")
    }

    @discardableResult
    private func runFastboot(serial: String, args: [String]) -> Int32 {
        let candidates = [
            Bundle.main.bundleURL.appendingPathComponent("fastboot").path,
            "/opt/homebrew/bin/fastboot",
            "/usr/local/bin/fastboot"
        ]
        let exec = candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? "/usr/local/bin/fastboot"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: exec)
        process.arguments = ["-s", serial] + args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            return -1
        }
    }
    private struct FastbootInstructionsView: View {
        var body: some View {
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
                .frame(maxHeight: 180)
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
    }
}

#Preview {
    UnlockView()
}

