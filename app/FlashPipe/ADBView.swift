//
//  ADBView.swift
//  FlashPipe
//
//  Created by Ancient Kira on 11/23/25.
//

import SwiftUI
import Combine
import OSLog
// Assuming ADBDevicesViewModel is now defined externally

private protocol SamsungDetecting {
    func isSamsung(serial: String) -> Bool
}

struct ADBView: View {
    @EnvironmentObject private var nav: AppNavigation
    // Assuming ADBDevicesViewModel is defined externally
    @StateObject private var viewModel = ADBDevicesViewModel()
    @State private var showConfirmReboot = false
    @State private var isSearching = false

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
        .navigationTitle("ADB Devices")
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

            ADBInstructionsView()
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

                Text("Please ensure your Android device is connected and USB debugging is enabled.")
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
        VStack(alignment: .leading, spacing: 16) {
            
            Text(viewModel.devices.count > 1 ? "Devices Detected" : "Device Detected")
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
                Picker("Select Device", selection: $viewModel.selectedDevice) {
                    ForEach(viewModel.devices, id: \.self) { device in
                        Text(device).tag(device as String?)
                    }
                }
                .pickerStyle(.menu)
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
                showConfirmReboot = true
            } label: {
                Text( (viewModel.selectedDevice.flatMap { isSamsungDevice(serial: $0) } ?? false) ? "Continue & Reboot to Download Mode" : "Continue & Reboot to Bootloader" )
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .alert("App will reboot your device into bootloader. You will have to flash a custom recovery of your choice tht is made for your device in order to flash a custom ROM. For a GSI, you will need a GSI of your choice. If your ROM has got individual images, the app will handle them. Continue?", isPresented: $showConfirmReboot) {
                Button("Cancel", role: .cancel) {}
                Button("Continue", role: .destructive) {
                    if let serial = viewModel.selectedDevice {
                        if isSamsungDevice(serial: serial) {
                            reboot(serial: serial, mode: "download")
                        } else {
                            reboot(serial: serial, mode: "bootloader")
                        }
                        nav.selection = .fastboot
                    }
                }
            }

            Menu {
                Button("Recovery") {
                    if let serial = viewModel.selectedDevice {
                        reboot(serial: serial, mode: "recovery")
                    }
                }
                Button("Normal Reboot") {
                    if let serial = viewModel.selectedDevice {
                        reboot(serial: serial, mode: nil)
                    }
                }
                Button("Fastboot") {
                    if let serial = viewModel.selectedDevice {
                        reboot(serial: serial, mode: "bootloader")
                    }
                }
                Button("(Samsung-only) Download mode") {
                    if let serial = viewModel.selectedDevice {
                        reboot(serial: serial, mode: "download")
                    }
                }
            } label: {
                Label("Reboot…", systemImage: "arrow.triangle.2.circlepath")
                    .frame(maxWidth: .infinity)
            }
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
        // Resolve adb path: prefer bundled next to app, then Homebrew Apple Silicon, then Intel
        let adbURL: URL = {
            if let execURL = Bundle.main.executableURL {
                let bundled = execURL.deletingLastPathComponent().appendingPathComponent("adb")
                if FileManager.default.isExecutableFile(atPath: bundled.path) {
                    return bundled
                }
            }
            let candidates = [
                "/opt/homebrew/bin/adb", // Apple Silicon Homebrew
                "/usr/local/bin/adb"     // Intel Homebrew or legacy
            ]
            if let found = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
                return URL(fileURLWithPath: found)
            }
            // Last resort: try Apple Silicon path
            return URL(fileURLWithPath: "/opt/homebrew/bin/adb")
        }()

        let fullArgs: [String]
        if !serial.isEmpty {
            fullArgs = ["-s", serial] + args
        } else {
            fullArgs = args
        }

        let process = Process()
        process.executableURL = adbURL
        process.arguments = fullArgs

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            process.currentDirectoryURL = URL(fileURLWithPath: "/")
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8), !output.isEmpty {
            }
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
        let realSerial = serial.extractSerial()
        _ = runADB(serial: realSerial, args: arguments)
    }

    private func isSamsungDevice(serial: String) -> Bool {
        // If the view model provides a better detection, prefer it. Otherwise, fallback to string heuristics.
        if let detector = (viewModel as AnyObject) as? SamsungDetecting {
            return detector.isSamsung(serial: serial)
        }
        // Heuristic: check the device listing string for manufacturer hints
        // Common adb `devices -l` output may include brand/model; here we only have the serial string, so allow broader matching if serial contains samsung-specific prefixes.
        let lower = serial.lowercased()
        return lower.contains("samsung") || lower.hasPrefix("sm-")
    }
}

private struct ADBInstructionsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("ADB Setup Instructions", systemImage: "info.circle")
                .font(.subheadline)
                
            ScrollView {
                Text(
                    """
                    If your device doesn’t appear, enable Developer options and USB debugging (steps vary by device):

                    1. Developer options
                       • Most devices: Settings → About phone → tap “Build number” seven times.
                       • MIUI/HyperOS: Settings → About phone → tap “MIUI version” seven times.

                    2. USB debugging
                       • Open Developer options (System → Developer options, or Additional settings → Developer options on MIUI/HyperOS).
                       • Turn on USB debugging.

                    3. Connect & trust
                       • Connect via USB.
                       • When prompted on the device, allow USB debugging (you can select “Always allow from this computer”).
                       • Click Refresh above.
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
final class ADBDevicesViewModel: ObservableObject {
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
                let fileMap = Self.readKnownFile()
                for (index, serial) in newDevices.enumerated() {
                    group.addTask {
                        // 1. Fetch codename:
                        let rawCode = (try? await Self.runShellCommand(["/bin/zsh","-lc","adb -s \(serial) shell getprop ro.product.device"]).get()) ?? ""
                        let code = rawCode.trimmingCharacters(in: .whitespacesAndNewlines)
                        // 2. Load TXT map once:
                        let fromTXT = fileMap[code]
                        // Check duplicates: if this name appears more than once, skip TXT
                        if let name = fromTXT {
                            let occurrences = fileMap.values.filter { $0 == name }.count
                            if occurrences == 1 {
                                // safe unique match → use TXT mapping
                                return (index, "\(name) (\(serial))")
                            }
                            // duplicates found → skip TXT and continue to model fallback
                        }
                        // 4. Fetch model:
                        let rawModel = (try? await Self.runShellCommand(["/bin/zsh","-lc","adb -s \(serial) shell getprop ro.product.model"]).get()) ?? ""
                        let model = rawModel.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !model.isEmpty {
                            return (index, "\(model) (\(serial))")
                        }
                        // 5. Fetch brand:
                        let rawBrand = (try? await Self.runShellCommand(["/bin/zsh","-lc","adb -s \(serial) shell getprop ro.product.brand"]).get()) ?? ""
                        let brand = rawBrand.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !brand.isEmpty {
                            return (index, "\(brand) (\(serial))")
                        }
                        // 6. Final fallback:
                        return (index, "\(code) (\(serial))")
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
                // Reject Sideload only
                if line.contains("\tsideload") { return nil }
                
                // Accept ANY state that contains a TAB after the serial
                guard let tab = line.firstIndex(of: "\t") else { return nil }

                let serial = String(line[..<tab]).trimmingCharacters(in: .whitespacesAndNewlines)
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
    ADBView()
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

