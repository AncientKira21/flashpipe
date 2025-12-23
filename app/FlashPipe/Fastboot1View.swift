//
//  Fastboot1View.swift
//  FlashPipe
//
//  Created by Ancient Kira on 04/28/24.
//

import SwiftUI
import Combine
import OSLog
import UniformTypeIdentifiers

struct Fastboot1View: View {
    @EnvironmentObject private var nav: AppNavigation
    @StateObject private var viewModel = FastbootDevicesViewModel()
    @State private var showConfirmReboot = false
    @State private var isSearching = false
    @State private var showFlashConfirm = false
    @State private var showFlashSuccessConfirm = false
    @State private var showFlashErrorSheet = false
    @State private var flashErrorText: String = ""
    @State private var showGSIConfirm = false
    @State private var vbmetaURL: URL?
    @State private var gsiURL: URL?
    @State private var showFlashLogoConfirm = false
    @State private var showFlashLogoSuccessConfirm = false
    @State private var showFlashLogoErrorSheet = false
    @State private var flashLogoErrorText: String = ""
    @State private var gsiErrorText: String = ""
    @State private var showGSIErrorSheet = false
    @State private var showGSISuccessConfirm = false

    @State private var showFlashLogoImporter = false
    @State private var logoFileToFlash: URL?
    @State private var showFlashRecoveryImporter = false
    @State private var recoveryFileToFlash: URL?

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 20) {
                contentView
            }
        }
        .padding()
        .frame(minWidth: 400, minHeight: 400)
        .onAppear {
            viewModel.startScanning()
            startSearchWindow()
        }
        .onDisappear { viewModel.stopScanning() }
        .navigationTitle("Fastboot")
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
    }

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

            Button {
                if let targetDevice = selectedOrFirstDevice() {
                    Task {
                        // Reboot to system using fastboot binary
                        _ = runFastboot(serial: targetDevice.serial, args: ["reboot"])
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        viewModel.startScanning()
                        startSearchWindow()
                    }
                }
            } label: {
                Text("Reboot to System")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)


            Menu {
                Button("Recovery") {
                    // Use NSOpenPanel directly for custom recovery flashing
                    let panel = NSOpenPanel()
                    panel.message = "Select a custom recovery image (.img)"
                    panel.allowedContentTypes = [UTType(filenameExtension: "img")!]
                    panel.allowsMultipleSelection = false

                    if panel.runModal() == .OK, let selected = panel.url, let targetDevice = selectedOrFirstDevice() {
                        DispatchQueue.global(qos: .userInitiated).async {
                            let status = runFastboot(serial: targetDevice.serial,
                                                     args: ["flash", "recovery", selected.path])
                            DispatchQueue.main.async {
                                if status == 0 {
                                    showFlashSuccessConfirm = true
                                } else {
                                    flashErrorText = "Flashing recovery failed. Ensure file is correct for this device."
                                    showFlashErrorSheet = true
                                }
                            }
                        }
                    }
                }
                Button("Logo") {
                    showFlashLogoImporter = true
                }
                Button("GSI") {
                    showGSIConfirm = true
                }
            } label: {
                Label("Flash…", systemImage: "bolt")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .fileImporter(
                isPresented: $showFlashLogoImporter,
                allowedContentTypes: [
                    UTType(filenameExtension: "img")!,
                    UTType(filenameExtension: "bin")!
                ],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let selectedFile = urls.first, let targetDevice = selectedOrFirstDevice() {
                        DispatchQueue.global(qos: .userInitiated).async {
                            let status = runFastboot(serial: targetDevice.serial, args: ["flash", "logo", selectedFile.path])
                            DispatchQueue.main.async {
                                if status == 0 {
                                    showFlashLogoSuccessConfirm = true
                                } else {
                                    flashLogoErrorText = "Flashing logo failed. Please check the device and file."
                                    showFlashLogoErrorSheet = true
                                }
                            }
                        }
                    }
                case .failure(let error):
                    flashLogoErrorText = "Failed to select file: \(error.localizedDescription)"
                    showFlashLogoErrorSheet = true
                }
            }
            // GSI confirmation alert after Button("GSI") { showGSIConfirm = true }
            .alert("WARNING: Flashing a GSI will wipe all data.", isPresented: $showGSIConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Continue") {
                    let panel = NSOpenPanel()
                    panel.message = "Select the 'vbmeta.img' file."
                    panel.allowedContentTypes = [UTType(filenameExtension: "img")!]
                    panel.allowsMultipleSelection = false
                    if panel.runModal() == .OK, let vb = panel.url {
                        vbmetaURL = vb

                        let panel2 = NSOpenPanel()
                        panel2.message = "Select the GSI system image (system.img)."
                        panel2.allowedContentTypes = [UTType(filenameExtension: "img")!]
                        panel2.allowsMultipleSelection = false
                        if panel2.runModal() == .OK, let gsi = panel2.url, let target = selectedOrFirstDevice() {
                            gsiURL = gsi
                            DispatchQueue.global(qos: .userInitiated).async {
                                let s1 = runFastboot(serial: target.serial, args: ["--disable-verity", "--disable-verification", "flash", "vbmeta", vb.path])
                                let s2 = runFastboot(serial: target.serial, args: ["flash", "system", gsi.path])
                                let s3 = runFastboot(serial: target.serial, args: ["-w"])
                                DispatchQueue.main.async {
                                    if s1 == 0 && s2 == 0 && s3 == 0 {
                                        showGSISuccessConfirm = true
                                    } else {
                                        gsiErrorText = "GSI flashing failed. Check vbmeta and system image."
                                        showGSIErrorSheet = true
                                    }
                                }
                            }
                        }
                    }
                }
            } message: {
                Text("""
Flashing a GSI disables boot verification and WILL wipe user data.
Always BACK UP before doing this.

GSIs can brick your device if incorrect.
GSIs require the correct vbmeta.img.
GSIs are mostly compatible with Android 8+ devices.
Qualcomm devices have better GSI compatibility than MediaTek.

Learn more:
https://customrombay.org/posts/gsi_roms/
""")
            }

            Menu {
                Button("Recovery") {
                    if let serial = viewModel.selectedSerial ?? viewModel.devices.first?.serial {
                        reboot(serial: serial, mode: "recovery")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            viewModel.startScanning()
                            startSearchWindow()
                        }
                    }
                }
                Button("Normal Reboot") {
                    if let serial = viewModel.selectedSerial ?? viewModel.devices.first?.serial {
                        reboot(serial: serial, mode: nil)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            viewModel.startScanning()
                            startSearchWindow()
                        }
                    }
                }
                Button("Fastbootd") {
                    if let serial = viewModel.selectedSerial ?? viewModel.devices.first?.serial {
                        reboot(serial: serial, mode: "fastboot")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            viewModel.startScanning()
                            startSearchWindow()
                        }
                    }
                }
                Button("Fastboot") {
                    if let serial = viewModel.selectedSerial ?? viewModel.devices.first?.serial {
                        reboot(serial: serial, mode: "bootloader")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            viewModel.startScanning()
                            startSearchWindow()
                        }
                    }
                }
            } label: {
                Label("Reboot…", systemImage: "arrow.triangle.2.circlepath")
                    .frame(maxWidth: .infinity)
            }
        }
        .alert("Custom recovery flashed. Reboot to recovery?", isPresented: $showFlashSuccessConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Reboot") {
                if let serial = viewModel.selectedSerial ?? viewModel.devices.first?.serial {
                    reboot(serial: serial, mode: "recovery")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        viewModel.startScanning()
                        startSearchWindow()
                    }
                }
            }
        }
        .sheet(isPresented: $showFlashErrorSheet) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Flashing Failed")
                    .font(.headline)
                ScrollView {
                    Text(flashErrorText.isEmpty ? "Unknown error" : flashErrorText)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 150, maxHeight: 300)
                HStack {
                    Spacer()
                    Button("Dismiss") { showFlashErrorSheet = false }
                }
            }
            .padding()
            .frame(minWidth: 420)
        }
        .sheet(isPresented: $showGSIErrorSheet) {
            VStack(alignment: .leading, spacing: 12) {
                Text("GSI Flash Failed")
                    .font(.headline)
                ScrollView {
                    Text(gsiErrorText.isEmpty ? "Unknown error" : gsiErrorText)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 150, maxHeight: 300)
                HStack {
                    Spacer()
                    Button("Dismiss") { showGSIErrorSheet = false }
                }
            }
            .padding()
            .frame(minWidth: 420)
        }
        .alert("GSI flashed successfully. Reboot to system?", isPresented: $showGSISuccessConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Reboot") {
                if let serial = viewModel.selectedSerial ?? viewModel.devices.first?.serial {
                    reboot(serial: serial, mode: nil)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        viewModel.startScanning()
                        startSearchWindow()
                    }
                }
            }
        }
    }

    private func selectedOrFirstDevice() -> FastbootDevice? {
        if let selected = viewModel.selectedSerial {
            return viewModel.devices.first(where: { $0.serial == selected })
        } else {
            return viewModel.devices.first
        }
    }

    private func startSearchWindow() {
        isSearching = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            if viewModel.devices.isEmpty {
                isSearching = false
            }
        }
    }

    @discardableResult
    private func runFastboot(serial: String, args: [String]) -> Int32 {
        let fastbootURL: URL = {
            if let execURL = Bundle.main.executableURL {
                let bundled = execURL.deletingLastPathComponent().appendingPathComponent("fastboot")
                if FileManager.default.isExecutableFile(atPath: bundled.path) {
                    return bundled
                }
            }
            let candidates = [
                "/opt/homebrew/bin/fastboot",
                "/usr/local/bin/fastboot"
            ]
            if let found = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
                return URL(fileURLWithPath: found)
            }
            return URL(fileURLWithPath: "/opt/homebrew/bin/fastboot")
        }()
        let fullArgs: [String] = serial.isEmpty ? args : ["-s", serial] + args
        let process = Process()
        process.executableURL = fastbootURL
        process.arguments = fullArgs
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            let _ = pipe.fileHandleForReading.readDataToEndOfFile()
            return process.terminationStatus
        } catch {
            return -1
        }
    }

    private func runFastbootWithOutput(serial: String, args: [String]) -> (status: Int32, output: String) {
        let fastbootURL: URL = {
            if let execURL = Bundle.main.executableURL {
                let bundled = execURL.deletingLastPathComponent().appendingPathComponent("fastboot")
                if FileManager.default.isExecutableFile(atPath: bundled.path) {
                    return bundled
                }
            }
            let candidates = [
                "/opt/homebrew/bin/fastboot",
                "/usr/local/bin/fastboot"
            ]
            if let found = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
                return URL(fileURLWithPath: found)
            }
            return URL(fileURLWithPath: "/opt/homebrew/bin/fastboot")
        }()
        let fullArgs: [String] = serial.isEmpty ? args : ["-s", serial] + args
        let process = Process()
        process.executableURL = fastbootURL
        process.arguments = fullArgs
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            return (process.terminationStatus, output)
        } catch {
            return (-1, "Failed to run fastboot: \(error)")
        }
    }

    private func reboot(serial: String, mode: String?) {
        var arguments = ["reboot"]
        if let mode, !mode.isEmpty {
            arguments.append(mode)
        }
        _ = runFastboot(serial: serial, args: arguments)
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

#Preview {
    Fastboot1View()
        .environmentObject(AppNavigation())
}

