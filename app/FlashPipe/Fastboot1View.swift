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
    // GSI flashing state/progress
    @State private var isGSIFlashing = false
    @State private var gsiProgress: Double = -1   // -1 = bouncing, 0...1 = percent
    @State private var gsiStatusText: String = "Preparing…"
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
    @State private var pendingMenuAction: String? = nil
    @State private var pendingMenuSerial: String? = nil
    @State private var isFilePickerActive = false
    @State private var isRecoveryFlashInProgress = false
    

    private var isMacOS26OrNewer: Bool {
        #if os(macOS)
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return v.majorVersion >= 26
        #else
        return false
        #endif
    }

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
            
            NotificationCenter.default.addObserver(forName: Notification.Name("FlashPipe_Fastboot_ApplySelection"), object: nil, queue: .main) { note in
                let serial = note.userInfo?["serial"] as? String
                let action = note.userInfo?["action"] as? String
                self.pendingMenuSerial = serial
                self.pendingMenuAction = action
                self.handlePendingMenuAction()
            }
            NotificationCenter.default.addObserver(forName: Notification.Name("FlashPipe_FB_Reboot_Normal"), object: nil, queue: .main) { _ in
                self.pendingMenuAction = "rebootNormal"
                self.handlePendingMenuAction()
            }
            NotificationCenter.default.addObserver(forName: Notification.Name("FlashPipe_FB_Reboot_Fastboot"), object: nil, queue: .main) { _ in
                self.pendingMenuAction = "rebootBootloader"
                self.handlePendingMenuAction()
            }
            NotificationCenter.default.addObserver(forName: Notification.Name("FlashPipe_FB_Reboot_Fastbootd"), object: nil, queue: .main) { _ in
                self.pendingMenuAction = "rebootFastbootd"
                self.handlePendingMenuAction()
            }
            NotificationCenter.default.addObserver(forName: Notification.Name("FlashPipe_FB_Reboot_Recovery"), object: nil, queue: .main) { _ in
                self.pendingMenuAction = "rebootRecovery"
                self.handlePendingMenuAction()
            }
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
            Button {
                nav.selection = .unlockBoot
            } label: {
                Label(NSLocalizedString("Unlock Bootloader", comment: ""), systemImage: "lock.open")
                    .font(.body)
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)


            Menu {
                // PATCH A: Recovery flash (button inside Flash… menu) with picker lock
                Button {
                    guard !isFilePickerActive else { return }
                    isFilePickerActive = true

                    let panel = NSOpenPanel()
                    panel.message = "Select a custom recovery image (.img)"
                    panel.allowedContentTypes = [UTType(filenameExtension: "img")!]
                    panel.allowsMultipleSelection = false

                    if panel.runModal() == .OK,
                       let selected = panel.url,
                       let targetDevice = selectedOrFirstDevice() {

                        DispatchQueue.global(qos: .userInitiated).async {
                            let status = runFastboot(serial: targetDevice.serial,
                                                     args: ["flash", "recovery", selected.path])
                            DispatchQueue.main.async {
                                self.isFilePickerActive = false
                                if status == 0 { self.showFlashSuccessConfirm = true }
                                else {
                                    self.flashErrorText = "Flashing recovery failed. Ensure file is correct for this device."
                                    self.showFlashErrorSheet = true
                                }
                            }
                        }
                    } else {
                        isFilePickerActive = false
                    }
                } label: {
                    if isMacOS26OrNewer {
                        Label("Recovery", systemImage: "wrench")
                    } else {
                        Text("Recovery")
                    }
                }
                // PATCH B: Logo flash (button inside Flash… menu) with picker lock
                Button {
                    guard !isFilePickerActive else { return }
                    isFilePickerActive = true
                    showFlashLogoImporter = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        isFilePickerActive = false
                    }
                } label: {
                    if isMacOS26OrNewer {
                        Label("Logo", systemImage: "photo")
                    } else {
                        Text("Logo")
                    }
                }
                // PATCH C: GSI flash (button inside Flash… menu) with picker lock
                Button {
                    guard !isFilePickerActive else { return }
                    isFilePickerActive = true
                    showGSIConfirm = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        isFilePickerActive = false
                    }
                } label: {
                    if isMacOS26OrNewer {
                        Label("GSI", systemImage: "square.stack.3d.up")
                    } else {
                        Text("GSI")
                    }
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
            // PATCH C(2): NSOpenPanels in GSI confirm alert with picker lock guards
            .alert("WARNING: Flashing a GSI will wipe all data.", isPresented: $showGSIConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Continue") {
                    guard !isFilePickerActive else { return }
                    isFilePickerActive = true
                    let panel = NSOpenPanel()
                    panel.message = "Select the 'vbmeta.img' file."
                    panel.allowedContentTypes = [UTType(filenameExtension: "img")!]
                    panel.allowsMultipleSelection = false
                    if panel.runModal() == .OK, let vb = panel.url, let target = selectedOrFirstDevice() {
                        vbmetaURL = vb
                        // Step 1: Flash vbmeta, no progress UI, just run and on completion go to system.img picker
                        DispatchQueue.global(qos: .userInitiated).async {
                            let vbmetaStatus = runFastboot(serial: target.serial, args: ["--disable-verity", "--disable-verification", "flash", "vbmeta", vb.path])
                            DispatchQueue.main.async {
                                if vbmetaStatus != 0 {
                                    isFilePickerActive = false
                                    gsiErrorText = "Failed to flash vbmeta.img."
                                    showGSIErrorSheet = true
                                    return
                                }
                                // Step 2: system.img picker (panel2)
                                let panel2 = NSOpenPanel()
                                panel2.message = "Select the GSI system image (system.img)."
                                panel2.allowedContentTypes = [UTType(filenameExtension: "img")!]
                                panel2.allowsMultipleSelection = false
                                if panel2.runModal() == .OK, let gsi = panel2.url {
                                    gsiURL = gsi
                                    // Step 3: Start GSI flashing flow
                                    flashGSI(serial: target.serial, systemPath: gsi.path)
                                } else {
                                    isFilePickerActive = false
                                }
                            }
                        }
                    } else {
                        isFilePickerActive = false
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
            // GSI flashing sheet
            .sheet(isPresented: $isGSIFlashing) {
                VStack(spacing:16){
                    Text(gsiStatusText)
                    if gsiProgress < 0 {
                        ProgressView().progressViewStyle(.linear).frame(width:260)
                    } else {
                        ProgressView(value:gsiProgress).progressViewStyle(.linear).frame(width:260)
                    }
                    if gsiProgress >= 0 {
                        Text("\(Int(gsiProgress*100))%")
                    }
                    Text("Do not disconnect your device.")
                }
                .padding(24)
                .frame(minWidth:300)
            }

            Menu {
                Button {
                    if let serial = viewModel.selectedSerial ?? viewModel.devices.first?.serial {
                        reboot(serial: serial, mode: "recovery")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            viewModel.startScanning()
                            startSearchWindow()
                        }
                    }
                } label: {
                    if isMacOS26OrNewer {
                        Label("Recovery", systemImage: "wrench")
                    } else {
                        Text("Recovery")
                    }
                }
                Button {
                    if let serial = viewModel.selectedSerial ?? viewModel.devices.first?.serial {
                        reboot(serial: serial, mode: nil)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            viewModel.startScanning()
                            startSearchWindow()
                        }
                    }
                } label: {
                    if isMacOS26OrNewer {
                        Label("Normal Reboot", systemImage: "arrow.clockwise")
                    } else {
                        Text("Normal Reboot")
                    }
                }
                Button {
                    if let serial = viewModel.selectedSerial ?? viewModel.devices.first?.serial {
                        reboot(serial: serial, mode: "fastboot")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            viewModel.startScanning()
                            startSearchWindow()
                        }
                    }
                } label: {
                    if isMacOS26OrNewer {
                        Label("Fastbootd", systemImage: "bolt.fill")
                    } else {
                        Text("Fastbootd")
                    }
                }
                Button {
                    if let serial = viewModel.selectedSerial ?? viewModel.devices.first?.serial {
                        reboot(serial: serial, mode: "bootloader")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            viewModel.startScanning()
                            startSearchWindow()
                        }
                    }
                } label: {
                    if isMacOS26OrNewer {
                        Label("Fastboot", systemImage: "bolt")
                    } else {
                        Text("Fastboot")
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
        .alert("Logo flashed. Reboot to system?", isPresented: $showFlashLogoSuccessConfirm) {
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

    // MARK: - GSI flashing logic
    private func flashGSI(serial: String, systemPath: String) {
        // Called from main thread after vbmeta and system.img are picked.
        // 1. Start erase system (bouncing)
        isGSIFlashing = true
        gsiProgress = -1
        gsiStatusText = "Erasing…"
        isFilePickerActive = false
        DispatchQueue.global(qos: .userInitiated).async {
            // Erase system (do NOT parse percentages, keep bouncing)
            let eraseProc = Process()
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
            eraseProc.executableURL = fastbootURL
            eraseProc.arguments = ["-s", serial, "erase", "system"]
            let erasePipe = Pipe()
            eraseProc.standardOutput = erasePipe
            eraseProc.standardError = erasePipe
            do {
                try eraseProc.run()
                eraseProc.waitUntilExit()
            } catch {
                DispatchQueue.main.async {
                    isGSIFlashing = false
                    gsiErrorText = "Failed to erase system: \(error)"
                    showGSIErrorSheet = true
                }
                return
            }
            // 2. Prepare for flashing (still bouncing)
            DispatchQueue.main.async {
                gsiStatusText = "Preparing…"
                gsiProgress = -1
            }
            // 3. Flash system.img with progress
            let flashProc = Process()
            flashProc.executableURL = fastbootURL
            flashProc.arguments = ["-s", serial, "flash", "system", systemPath]
            let flashPipe = Pipe()
            flashProc.standardOutput = flashPipe
            flashProc.standardError = flashPipe
            let fh = flashPipe.fileHandleForReading
            // Removed: var lastPercent: Double = 0
            // Removed: var didShowPercent = false
            // Read output line by line, parse "Sending sparse 'system' X/Y"
            let group = DispatchGroup()
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                var buffer = Data()
                while true {
                    let chunk = (try? fh.read(upToCount: 4096)) ?? Data()
                    if chunk.isEmpty { break }
                    buffer.append(chunk)
                    while let range = buffer.range(of: Data([0x0A])) {
                        let lineData = buffer.subdata(in: 0..<range.lowerBound)
                        buffer.removeSubrange(0...range.lowerBound)
                        if let line = String(data: lineData, encoding: .utf8) {
                            // Parse "Sending sparse 'system' X/Y"
                            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                            if let _ = trimmed.range(of: #"Sending sparse 'system' (\d+)/(\d+)"#, options: .regularExpression) {
                                let parts = trimmed.components(separatedBy: .whitespaces)
                                if let sparseIdx = parts.firstIndex(where: { $0.contains("sparse") }),
                                   parts.count > sparseIdx+2 {
                                    let fracPart = parts[sparseIdx+2] // "X/Y"
                                    let nums = fracPart.components(separatedBy: "/")
                                    if nums.count == 2, let x = Double(nums[0]), let y = Double(nums[1]), y > 0 {
                                        let fraction = x / y
                                        // Removed: lastPercent = fraction
                                        // Removed: didShowPercent = true
                                        DispatchQueue.main.async {
                                            gsiProgress = fraction
                                            gsiStatusText = "Flashing… \(Int(fraction*100))%"
                                        }
                                    }
                                }
                            }
                            // If line indicates writing OKAY, do not update percent, just keep last
                            // (We do not reset progress here)
                        }
                    }
                }
                group.leave()
            }
            do {
                try flashProc.run()
                flashProc.waitUntilExit()
                group.wait()
            } catch {
                DispatchQueue.main.async {
                    isGSIFlashing = false
                    gsiErrorText = "Failed to flash system: \(error)"
                    showGSIErrorSheet = true
                }
                return
            }
            // After system flash, run fastboot -w (bouncing, "Erasing…")
            DispatchQueue.main.async {
                gsiProgress = -1
                gsiStatusText = "Erasing…"
            }
            let wipeProc = Process()
            wipeProc.executableURL = fastbootURL
            wipeProc.arguments = ["-s", serial, "-w"]
            let wipePipe = Pipe()
            wipeProc.standardOutput = wipePipe
            wipeProc.standardError = wipePipe
            do {
                try wipeProc.run()
                wipeProc.waitUntilExit()
            } catch {
                DispatchQueue.main.async {
                    isGSIFlashing = false
                    gsiErrorText = "Failed to wipe userdata: \(error)"
                    showGSIErrorSheet = true
                }
                return
            }
            // Success!
            DispatchQueue.main.async {
                isGSIFlashing = false
                showGSISuccessConfirm = true
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
    
    private func handlePendingMenuAction() {
        // Ensure scanning so the sheet shows up-to-date devices
        viewModel.startScanning()
        startSearchWindow()
        // If a serial was preselected from the sheet, set it; otherwise leave picker to user
        if let pre = pendingMenuSerial, !pre.isEmpty {
            viewModel.selectedSerial = pre
        }
        // Present a lightweight sheet to select device if none selected
        if viewModel.selectedSerial == nil {
            // Trigger the sheet by toggling a local @State that we already have via FastbootDevicePickerSheet in App
            // Here, we do nothing; the App already presented the sheet before posting this notification.
        }
        // Execute action if available
        guard let action = pendingMenuAction else { return }
        executeMenuAction(action: action)
        // Clear pending
        pendingMenuAction = nil
        pendingMenuSerial = nil
    }
    
    private func executeMenuAction(action: String) {
        let serial = viewModel.selectedSerial ?? viewModel.devices.first?.serial ?? pendingMenuSerial ?? ""
        guard !serial.isEmpty else { return }
        switch action {
        case "recovery":
            guard !isRecoveryFlashInProgress else { return }
            isRecoveryFlashInProgress = true
            guard !isFilePickerActive else { return }
            isFilePickerActive = true

            let panel = NSOpenPanel()
            panel.message = "Select a custom recovery image (.img)"
            panel.allowedContentTypes = [UTType(filenameExtension: "img")!]
            panel.allowsMultipleSelection = false

            if panel.runModal() == .OK, let selected = panel.url {
                DispatchQueue.global(qos: .userInitiated).async {
                    let status = runFastboot(serial: serial, args: ["flash", "recovery", selected.path])
                    DispatchQueue.main.async {
                        self.isFilePickerActive = false
                        self.isRecoveryFlashInProgress = false

                        if status == 0 {
                            self.showFlashSuccessConfirm = true
                        } else {
                            self.flashErrorText = "Flashing recovery failed. Ensure file is correct for this device."
                            self.showFlashErrorSheet = true
                        }
                    }
                }
            } else {
                self.isFilePickerActive = false
                self.isRecoveryFlashInProgress = false
            }
        case "logo":
            guard !isFilePickerActive else { return }
            isFilePickerActive = true
            self.viewModel.selectedSerial = serial
            self.showFlashLogoImporter = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.isFilePickerActive = false
            }
        case "gsi":
            self.viewModel.selectedSerial = serial
            self.showGSIConfirm = true
        case "rebootNormal":
            reboot(serial: serial, mode: nil)
        case "rebootBootloader":
            reboot(serial: serial, mode: "bootloader")
        case "rebootFastbootd":
            reboot(serial: serial, mode: "fastboot")
        case "rebootRecovery":
            reboot(serial: serial, mode: "recovery")
        default:
            break
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
//        .environmentObject(AppNavigation())
}

