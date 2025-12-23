//
//  FlashROM1View.swift
//  FlashPipe
//
//  Created by Ancient Kira on 11/23/25.
//  Binaries are bundled within the app in Contents/MacOS, so there's no need to use this Mac's adb.
//

import SwiftUI
import Combine
import OSLog
import UniformTypeIdentifiers
// Using UTType explicitly for fileImporter allowedContentTypes

// Assuming ADBDevicesViewModel is now defined externally

struct FlashROM1View: View {
    @EnvironmentObject private var nav: AppNavigation
    // Assuming ADBDevicesViewModel is defined externally
    @StateObject private var viewModel = ADBSideloadViewModel()
    @State private var showConfirmReboot = false
    @State private var isSearching = false
    @State private var showFlashConfirm = false
    @State private var isShowingFilePicker = false
    @State private var selectedROMFile: URL? = nil
    @State private var showFlashResult = false
    @State private var flashingError: String = ""
    @State private var isFlashing = false
    @State private var flashingTitle = ""
    @State private var sideloadProgress: Double = 0
    enum FlashMode { case normal, root, fbe }
    @State private var flashMode: FlashMode = .normal

    private func resetForNewImport() {
        // Ensure importer can present again
        isShowingFilePicker = false
        // Clear previously selected file to force a new import
        selectedROMFile = nil
        // Dismiss any result sheets
        showFlashResult = false
        // Ensure confirmation alert can re-present cleanly
        showFlashConfirm = false
    }

    var body: some View {
        VStack(spacing: 20) { // Increased vertical spacing for primary sections
            contentView
            
//            Spacer() // Push content up
        }
        .padding()
        .frame(minWidth: 400, minHeight: 400) // Slightly wider min width for better macOS feel
        .onAppear {
            viewModel.startAutoDetect()
            startSearchWindow()
        }
        .onDisappear { viewModel.cancelDetection() }
//        .navigationTitle("Flash ROM")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    viewModel.startAutoDetect()
                    startSearchWindow()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
        .alert("You are about to flash a ROM ZIP using ADB Sideload.\nMake sure your device is in Recovery → Apply update → Apply from ADB.\nThis process may wipe data depending on the ROM.\nContinue?", isPresented: $showFlashConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Continue", role: .destructive) {
                resetForNewImport()
                isShowingFilePicker = true
            }
        }
        .fileImporter(
            isPresented: $isShowingFilePicker,
            allowedContentTypes: [UTType.zip],
            allowsMultipleSelection: false
        ) { result in
            do {
                let url = try result.get().first!
                selectedROMFile = url
                startFlashingROM()
            } catch {
                resetForNewImport()
                flashingError = "Failed to select file: \(error.localizedDescription)"
                showFlashResult = true
            }
        }
        .sheet(isPresented: $isFlashing) {
            VStack(spacing: 16) {
                Text(sideloadProgress > 0 ? "Flashing… \(max(0, min(100, Int(sideloadProgress * 100))))%" : "Flashing…")
                    .font(.headline)

                if sideloadProgress <= 0 || sideloadProgress > 1 {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .frame(width: 260)
                } else {
                    ProgressView(value: sideloadProgress)
                        .progressViewStyle(.linear)
                        .frame(width: 260)
                }

                Text("\(max(0, min(100, Int(sideloadProgress * 100))))%")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("Do not disconnect your device.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(24)
            .frame(minWidth: 300)
        }
        .sheet(isPresented: $showFlashResult) {
            VStack(spacing: 20) {
                if flashingError.isEmpty {
                    // SUCCESS POPUP
                    Text("Operation successful!")
                        .font(.title2)
                        .foregroundColor(.green)

                    if flashMode == .normal {
                        // NORMAL FLASH → 3 buttons
                        Text("Flash complete! What's next?\n\nRoot your device, disable FBE, or reboot and enjoy your new ROM.")
                            .font(.body)
                            .multilineTextAlignment(.center)

                        HStack(spacing: 12) {
                            Button("Reboot") {
                                if let serial = viewModel.selectedDevice {
                                    let clean = serial.extractSerial()
                                    _ = runADB(serial: clean, args: ["reboot"])
                                }
                                resetForNewImport()
                                showFlashResult = false
                            }
                            .buttonStyle(.borderedProminent)

                            Button("Root") {
                                flashMode = .root
                                resetForNewImport()
                            }
                            .buttonStyle(.bordered)

                            Button("Disable FBE") {
                                flashMode = .fbe
                                resetForNewImport()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    else if flashMode == .root {
                        Text("Operation completed. Reboot now, or disable FBE.")
                            .font(.body)
                            .multilineTextAlignment(.center)

                        HStack(spacing: 12) {
                            Button("Reboot") {
                                if let serial = viewModel.selectedDevice {
                                    let clean = serial.extractSerial()
                                    _ = runADB(serial: clean, args: ["reboot"])
                                }
                                resetForNewImport()
                                showFlashResult = false
                            }
                            .buttonStyle(.borderedProminent)

                            Button("Disable FBE") {
                                flashMode = .fbe
                                resetForNewImport()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    else if flashMode == .fbe {
                        Text("Operation completed. Reboot now, or root your device.")
                            .font(.body)
                            .multilineTextAlignment(.center)

                        HStack(spacing: 12) {
                            Button("Reboot") {
                                if let serial = viewModel.selectedDevice {
                                    let clean = serial.extractSerial()
                                    _ = runADB(serial: clean, args: ["reboot"])
                                }
                                resetForNewImport()
                                showFlashResult = false
                            }
                            .buttonStyle(.borderedProminent)

                            Button("Root") {
                                flashMode = .root
                                resetForNewImport()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                } else {
                    // FAILURE POPUP
                    Text("Sideload Failed.")
                        .font(.title2)
                        .foregroundColor(.red)

                    ScrollView {
                        Text(flashingError)
                            .font(.caption)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 150)

                    Button("OK") {
                        showFlashResult = false
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(24)
            .frame(minWidth: 350)
        }
    }

    
    private var contentView: some View {
        VStack(spacing: 30) { // Large spacing between controls/status and instructions
            Group {
                if viewModel.devices.isEmpty {
                    emptyStateView
                } else {
                    deviceFoundView
                }
            }
            .frame(maxWidth: 350) // Constrain interaction elements horizontally

            ADBInstructionsView(flashMode: flashMode)
                .frame(maxWidth: 450)
        }
        // Align content centrally if the window is very large
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

                Text("Please ensure your Android device is connected and in sideload mode.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 10)
            
            Button {
                // Action disabled, but defined for consistency
            } label: {
                Text("Continue")
                    .frame(minWidth: 120) // Give the button a fixed minimum width
            }
            .buttonStyle(.borderedProminent)
            .disabled(true)
        }
        .padding(.vertical, 20)
    }
    
    private var deviceFoundView: some View {
        VStack (alignment: .leading,
        spacing: 16){
        Text (viewModel.devices.count > 1 ? "Devices Detected": "Device Detected")
                .font(.title3)
                .bold()

            if viewModel.devices.count == 1 {
                // Auto-select and show the single device without a dropdown
                let single = viewModel.devices.first!
                Text(single)
                    .font(.body)
                    .onAppear {
                        if viewModel.selectedDevice != single {
                            viewModel.selectedDevice = single
                        }
                    }
            } else if viewModel.devices.count > 1 {
                Picker("Select Device", selection: Binding<String>(get: { viewModel.selectedDevice ?? viewModel.devices.first ?? "" }, set: { viewModel.selectedDevice = $0.isEmpty ? nil : $0 })) {
                    ForEach(viewModel.devices, id: \.self) { device in
                        Text(device).tag(device)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: viewModel.selectedDevice) { _, newValue in
                }
            }

            // Display selected device status
            HStack {
                Text("Selected:")
                if viewModel.devices.count == 1, let single = viewModel.devices.first {
                    Text("\(single)")
                        .foregroundStyle(.primary)
                } else if let selected = viewModel.selectedDevice {
                    Text("\(selected)")
                        .foregroundStyle(.primary)
                } else {
                    Text("No device selected")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.subheadline)

            Spacer().frame(height: 10) // Visual separator before action button

            Button {
                showFlashConfirm = true
            } label: {
                Text(
                    flashMode == .normal ? "Flash ROM" :
                    flashMode == .root ? "Install Magisk/KernelSU" :
                    "Disable FBE"
                )
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            //.disabled(viewModel.selectedDevice == nil)
        }
    }

    private func startSearchWindow() {
        isSearching = true
        // Cancel any prior scheduled switch by resetting state; rely on latest DispatchWorkItem semantics here
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            // If devices were found, keep normal flow; otherwise show no devices state
            if viewModel.devices.isEmpty {
                isSearching = false
            }
        }
    }

    @discardableResult
    private func runADB(serial: String, args: [String]) -> Int32 {
        // Prefer system adb in Homebrew paths
        let candidates = [
            "/opt/homebrew/bin/adb",
            "/usr/local/bin/adb"
        ]
        
        var adbPath: String? = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
        
        if adbPath == nil {
            // Fallback to which adb via PATH
            let whichProcess = Process()
            let pipe = Pipe()
            whichProcess.executableURL = URL(fileURLWithPath: "/bin/zsh")
            whichProcess.arguments = ["-lc", "which adb"]
            whichProcess.standardOutput = pipe
            whichProcess.standardError = pipe
            do {
                try whichProcess.run()
                whichProcess.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !path.isEmpty && FileManager.default.isExecutableFile(atPath: path) {
                    adbPath = path
                }
            } catch {
                // ignore error, fallback remains nil
            }
        }
        
        guard let foundPath = adbPath else {
            return -1
        }

        let adbURL = URL(fileURLWithPath: foundPath)
        let fullArgs: [String] = serial.isEmpty ? args : ["-s", serial] + args

        let process = Process()
        process.executableURL = adbURL
        process.arguments = fullArgs

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            _ = pipe.fileHandleForReading.readDataToEndOfFile()
            return process.terminationStatus
        } catch {
            return -1
        }
    }

    private func runProcess(url: URL, serial: String, args: [String]) -> Int32 {
        let fullArgs: [String] = serial.isEmpty ? args : ["-s", serial] + args
        let process = Process()
        process.executableURL = url
        process.arguments = fullArgs
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            _ = pipe.fileHandleForReading.readDataToEndOfFile()
            return process.terminationStatus
        } catch {
            return -1
        }
    }

    private func reboot(serial: String, mode: String?) {
        var arguments = ["reboot"]
        if let mode, !mode.isEmpty {
            arguments.append(mode)
        }
        _ = runADB(serial: serial, args: arguments)
    }

    private struct ADBInstructionsView: View {
        let flashMode: FlashROM1View.FlashMode
        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                Text(
                    flashMode == .normal ? "ADB Sideload Instructions" :
                    flashMode == .root ? "Rooting Instructions" :
                    "Disable FBE Instructions"
                )
                .font(.subheadline)

                ScrollView {
                    Text(
                            flashMode == .normal ?
                            """
                            Follow these steps to install a ROM using ADB Sideload:
                                1. Reboot to Recovery
                                • Most devices: Power + Volume Up → Recovery Mode
                                • Pixel/Stock Android: Recovery → Apply update → Apply from ADB
                                • OrangeFox: Recovery → Settings → ADB & Sideload → Start Sideload
                                • PBRP: Unsupported, try OrangeFox.
                                2. Enable ADB Sideload Mode
                                • Select "Apply from ADB" in recovery.
                                3. Choose your ZIP.
                                4. Start the process using the button above.
                            """
                            :
                            flashMode == .root ?
                            """
                                                        Follow these steps to install a ROM using ADB Sideload:
                                                            1. Reboot to Recovery
                                                            • Most devices: Power + Volume Up → Recovery Mode
                                                            • Pixel/Stock Android: Recovery → Apply update → Apply from ADB
                                                            • OrangeFox: Recovery → Settings → ADB & Sideload → Start Sideload
                                                            • PBRP: Unsupported, try OrangeFox.
                                                            2. Enable ADB Sideload Mode
                                                            • Select "Apply from ADB" in recovery.
                            Rooting Instructions:
                                • Go Back and re-enter sideload mode.
                                • Download Magisk or KernelSU from the official website.
                                • Rename the .apk to .zip
                                • Press “Install Magisk/KernelSU” above to flash it.
                            """
                            :
                            """
                                                        Follow these steps to install a ROM using ADB Sideload:
                                                            1. Reboot to Recovery
                                                            • Most devices: Power + Volume Up → Recovery Mode
                                                            • Pixel/Stock Android: Recovery → Apply update → Apply from ADB
                                                            • OrangeFox: Recovery → Settings → ADB & Sideload → Start Sideload
                                                            • PBRP: Unsupported, try OrangeFox.
                                                            2. Enable ADB Sideload Mode
                                                            • Select "Apply from ADB" in recovery.
                            Disable FBE Instructions:
                                • Go Back and re-enter sideload mode.
                                • Download the FBE disabler zip online.
                                • Click Disable FBE to flash the zip.
                            Warnings:
                                • This disables File-Based Encryption.
                                • Data loss may occur on some ROMs.
                            """
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 180)
            }
            .padding(16)
            // Using `controlBackground` but adding a slight border for visual definition on macOS
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

    private func startFlashingROM() {
        guard let serial = viewModel.selectedDevice else { return }
        guard let file = selectedROMFile else { return }

        flashingTitle = "Flashing ROM…"
        flashingError = ""
        isFlashing = true
        sideloadProgress = 0

        func extractProgress(from text: String) -> Double {
            // Looks for (~47%) → returns 0.47
            let pattern = #"\(~(\d+)%\)"#
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let r = Range(match.range(at: 1), in: text),
               let value = Double(text[r]) {
                return value / 100.0
            }
            return sideloadProgress
        }
        
        // Resolve adb path with fallback like runADB
        let candidates = [
            "/opt/homebrew/bin/adb",
            "/usr/local/bin/adb"
        ]
        var adbPath: String? = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
        if adbPath == nil {
            let whichProcess = Process()
            let pipe = Pipe()
            whichProcess.executableURL = URL(fileURLWithPath: "/bin/zsh")
            whichProcess.arguments = ["-lc", "which adb"]
            whichProcess.standardOutput = pipe
            whichProcess.standardError = pipe
            do {
                try whichProcess.run()
                whichProcess.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !path.isEmpty && FileManager.default.isExecutableFile(atPath: path) {
                    adbPath = path
                }
            } catch {
                // ignore error
            }
        }
        guard let adbExecutable = adbPath else {
            DispatchQueue.main.async {
                isFlashing = false
                flashingError = "Tools not found. Please install tools in settings or with Homebrew."
                showFlashResult = true
            }
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let cleanSerial = serial.extractSerial()

            // Launch process manually to capture live output
            let process = Process()
            process.executableURL = URL(fileURLWithPath: adbExecutable)
            process.arguments = ["-s", cleanSerial, "sideload", file.path]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty { return }
                if let text = String(data: data, encoding: .utf8) {
                    DispatchQueue.main.async {
                        // Removed live flashingTitle update per instruction
                        // flashingTitle = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        let new = extractProgress(from: text)
                        sideloadProgress = new
                    }
                }
            }

            do {
                try process.run()
                process.waitUntilExit()
                pipe.fileHandleForReading.readabilityHandler = nil
                let _ = pipe.fileHandleForReading.readDataToEndOfFile()
            } catch {
                DispatchQueue.main.async {
                    isFlashing = false
                    flashingError = "ADB sideload failed."
                    showFlashResult = true
                }
                return
            }

            DispatchQueue.main.async {
                isFlashing = false
                if process.terminationStatus == 0 {
                    flashingError = ""
                    showFlashResult = true
                } else {
                    flashingError = "ADB sideload failed."
                    showFlashResult = true
                }
            }
        }
    }
}

final class ADBSideloadViewModel: ObservableObject {
    @Published var devices: [String] = []
    @Published var selectedDevice: String? = nil
    @Published var statusMessage: String = "Scanning for devices…"
    
    private var detectTask: Task<Void, Never>? = nil
    private let detectionInterval: Duration = .seconds(1)
    
    func startAutoDetect() {
        // Cancel any existing detection loop
        detectTask?.cancel()
        statusMessage = "Scanning for devices…"
        let start = ContinuousClock.now
        let clock = ContinuousClock()
        detectTask = Task { [weak self] in
            guard let self else { return }
            // let clock = ContinuousClock()
            // Poll until we find at least one device or 10 seconds elapse
            while !Task.isCancelled {
                await self.performRefreshOnce()
                if !self.devices.isEmpty { break }
                // Check timeout (10 seconds)
                let elapsed = clock.now - start
                if elapsed >= .seconds(10) { break }
                try? await Task.sleep(for: detectionInterval)
            }
        }
    }

    private func performRefreshOnce() async {
        let result = await Self.runADBDevices()
        switch result {
        case .success(let list):
            let newDevices = Self.parseADBList(list)

            // Build mapped list off the main actor, loading fileMap once and preserving order
            let mapped: [String] = await withTaskGroup(of: (Int, String)?.self) { group in
                for (index, serial) in newDevices.enumerated() {
                    group.addTask {
                        let raw = (try? await Self.runShellCommand(["/bin/zsh","-lc","adb -s \(serial) shell getprop ro.product.device"]).get()) ?? ""
                        let code = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                        let friendly = await DevicesCodenameResolver.friendly(for: code)
                        return (index, "\(friendly) (\(serial))")
                    }
                }

                var tmp: [(Int, String)] = []
                for await entry in group {
                    if let entry { tmp.append(entry) }
                }

                // Convert tmp into [(Int, String, String)] where (index, friendlyName, serial)
                let parsed: [(Int, String, String)] = tmp.compactMap { (idx, val) in
                    if let openParen = val.lastIndex(of: "("),
                       let closeParen = val.lastIndex(of: ")"),
                       openParen < closeParen
                    {
                        let friendly = String(val[..<openParen]).trimmingCharacters(in: .whitespacesAndNewlines)
                        let serial = String(val[val.index(after: openParen)..<closeParen]).trimmingCharacters(in: .whitespacesAndNewlines)
                        return (idx, friendly, serial)
                    }
                    return nil
                }

                // Count occurrences of each friendly name
                var counts: [String: Int] = [:]
                for (_, friendly, _) in parsed {
                    counts[friendly, default: 0] += 1
                }

                // For numbering duplicates
                var numbering: [String: Int] = [:]

                // Build final display names
                var result: [(Int, String)] = []
                for (idx, friendly, serial) in parsed {
                    if counts[friendly] == 1 {
                        result.append((idx, "\(friendly) (\(serial))"))
                    } else {
                        let num = (numbering[friendly] ?? 0) + 1
                        numbering[friendly] = num
                        result.append((idx, "\(friendly) \(num) (\(serial))"))
                    }
                }

                return result.sorted { $0.0 < $1.0 }.map { $0.1 }
            }

            // Assign on the main actor
            await MainActor.run {
                self.devices = mapped
                if self.selectedDevice == nil, let first = mapped.first {
                    self.selectedDevice = first
                }
            }

        case .failure:
            await MainActor.run {
                self.devices = []
                self.selectedDevice = nil
            }
        }
    }

    func cancelDetection() {
        detectTask?.cancel()
        detectTask = nil
    }

    // Other static helpers…

    static func runShellCommand(_ command: [String]) async -> Result<String, Error> {
        await withCheckedContinuation { continuation in
            let process = Process()
            let pipe = Pipe()

            // Expecting something like ["/bin/zsh", "-lc", "adb devices"]
            guard let executable = command.first else {
                continuation.resume(returning: .failure(NSError(domain: "RunShellCommand", code: -1, userInfo: [NSLocalizedDescriptionKey: "Empty command"])) )
                return
            }
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = Array(command.dropFirst())
            process.standardOutput = pipe
            process.standardError = pipe

            do {
                try process.run()
            } catch {
                continuation.resume(returning: .failure(error))
                return
            }

            process.terminationHandler = { proc in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                if proc.terminationStatus == 0 {
                    continuation.resume(returning: .success(output))
                } else {
                    let err = NSError(domain: "RunShellCommand", code: Int(proc.terminationStatus), userInfo: [NSLocalizedDescriptionKey: output.isEmpty ? "Command failed with status \(proc.terminationStatus)" : output])
                    continuation.resume(returning: .failure(err))
                }
            }
        }
    }

    private static func runADBDevices() async -> Result<String, Error> {
        await runShellCommand(["/bin/zsh", "-lc", "adb devices"])
    }

    private static func parseADBList(_ output: String) -> [String] {
        return output
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("List of devices") }
            .compactMap { line in
                
                // Accept ANY state that contains a TAB followed by "sideload" after the serial
                guard let range = line.range(of: "\tsideload") else { return nil }
                let serial = String(line[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                return serial.isEmpty ? nil : serial
            }
    }

    static func readKnownFile() -> [String: String] {
        guard let url = Bundle.main.url(forResource: "KnownDeviceCodenames", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return [:] }
        var map: [String: String] = [:]
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "=")
            if parts.count == 2 {
                let name = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let code = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                map[code] = name
            }
        }
        return map
    }
}


#Preview {
    FlashROM1View()
        .environmentObject(AppNavigation())
}

private extension String {
    func extractSerial() -> String {
        if let open = self.lastIndex(of: "("),
           let close = self.lastIndex(of: ")"),
           open < close {
            return String(self[self.index(after: open)..<close])
        }
        return self
    }
}

