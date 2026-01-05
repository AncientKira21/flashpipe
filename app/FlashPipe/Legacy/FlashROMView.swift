// //
// //  FlashROMView.swift
// //  FlashPipe
// //
// //  Created by Ancient Kira on 11/23/25.
// //
//
// import SwiftUI
// import Combine
//
// struct FlashROMView: View {
//     @EnvironmentObject private var nav: AppNavigation
//     @StateObject private var viewModel = ADBDevicesViewModel()
//     @State private var showConfirmReboot = false
//
//     var body: some View {
//         VStack(alignment: .leading, spacing: 16) {
//             
//             HStack {
//                 Text("ADB Devices")
//                     .font(.headline)
//                 Spacer()
//                 Button {
//                     viewModel.startAutoDetect()
//                 } label: {
//                     Label("Refresh", systemImage: "arrow.clockwise")
//                 }
//                 .keyboardShortcut("r", modifiers: [.command])
//             }
//
//             if viewModel.devices.isEmpty {
//                 VStack(alignment: .leading, spacing: 12) {
//                     HStack(spacing: 8) {
//                         ProgressView()
//                         Text(viewModel.statusMessage)
//                             .foregroundStyle(.secondary)
//                     }
//
//                     ADBInstructionsView()
//
//                     Button {
//                         showConfirmReboot = true
//                     } label: {
//                         Text("Continue")
//                     }
//                     .buttonStyle(.borderedProminent)
//                     .disabled(true)
//                 }
//             } else {
//                 Picker("Select Device", selection: $viewModel.selectedDevice) {
//                     ForEach(viewModel.devices, id: \.self) { device in
//                         Text(device).tag(Optional(device))
//                     }
//                 }
//                 .pickerStyle(.menu)
//
//                 if let selected = viewModel.selectedDevice {
//                     Text("Selected: \(selected)")
//                         .font(.subheadline)
//                         .foregroundStyle(.secondary)
//                 }
//
//                 Button {
//                     showConfirmReboot = true
//                 } label: {
//                     Text("Continue")
//                 }
//                 .buttonStyle(.borderedProminent)
//                 .disabled(viewModel.selectedDevice == nil)
//                 .alert("App will reboot your device into bootloader. You will have to flash a custom recovery of your choice tht is made for your device in order to flash a custom ROM. For a GSI, you will need a GSI of your choice. If your ROM has got individual images, the app will handle them. Continue?", isPresented: $showConfirmReboot) {
//                     Button("Cancel", role: .cancel) {}
//                     Button("Continue", role: .destructive) {
//                         if let serial = viewModel.selectedDevice {
//                             viewModel.rebootToBootloader(serial: serial)
//                             nav.selection = .fastboot
//                         }
//                     }
//                 }
//
//                 ADBInstructionsView()
//             }
//
//             Spacer()
//         }
//         .padding()
//         .onAppear {
//             viewModel.startAutoDetect()
//         }
//         .onDisappear { viewModel.cancelDetection() }
//     }
// }
//
// private struct ADBInstructionsView: View {
//     var body: some View {
//         HStack(alignment: .top, spacing: 8) {
//             Image(systemName: "info.circle")
//                 .foregroundStyle(.blue)
//             Text("If your device doesn’t appear, enable Developer Options and USB debugging on your Android device (steps can vary by device):\n\n1) Most devices: Settings > About phone, then tap Build number seven times to enable Developer Options.\n2) Go back to Settings > System > Developer options. When you're in Developer options, enable USB debugging.\n\nMIUI/HyperOS: Go to About phone and tap MIUI version seven times. Then go back to Settings > Additional settings > Developer options. When you're in Developer options, enable USB debugging.\n\n3) Connect your device via USB, click Refresh here, and if prompted on the device, grant permission (Always allow from this computer). The rest of the steps are the same across Android devices.")
//                 .foregroundStyle(.secondary)
//         }
//     }
// }
//
// @MainActor
// final class ADBDevicesViewModel: ObservableObject {
//     @Published var devices: [String] = []
//     @Published var selectedDevice: String? = nil
//     @Published var statusMessage: String = "Scanning for devices…"
//
//     private var detectTask: Task<Void, Never>? = nil
//     private let detectionInterval: Duration = .seconds(1)
//
//     func startAutoDetect() {
//         // Cancel any existing detection loop
//         detectTask?.cancel()
//         statusMessage = "Scanning for devices…"
//         let start = ContinuousClock.now
//         detectTask = Task { [weak self] in
//             guard let self else { return }
//             let clock = ContinuousClock()
//             // Poll until we find at least one device or 10 seconds elapse
//             while !Task.isCancelled {
//                 await self.performRefreshOnce()
//                 if !self.devices.isEmpty { break }
//                 // Check timeout (10 seconds)
//                 let elapsed = clock.now - start
//                 if elapsed >= .seconds(10) { break }
//                 try? await Task.sleep(for: detectionInterval)
//             }
//         }
//     }
//
//     func cancelDetection() {
//         detectTask?.cancel()
//         detectTask = nil
//     }
//
//     private func performRefreshOnce() async {
//         let result = await Self.runADBDevices()
//         switch result {
//         case .success(let list):
//             let parsed = Self.parseADBDevicesOutput(list)
//             await MainActor.run {
//                 self.devices = parsed
//                 if let first = parsed.first {
//                     if self.selectedDevice == nil || !(parsed.contains(self.selectedDevice!)) {
//                         self.selectedDevice = first
//                     }
//                 } else {
//                     self.selectedDevice = nil
//                 }
//                 self.statusMessage = parsed.isEmpty ? "No devices found" : "Found \(parsed.count) device(s)"
//             }
//         case .failure(let error):
//             await MainActor.run {
//                 self.devices = []
//                 self.selectedDevice = nil
//                 self.statusMessage = "Error: \(error.localizedDescription)"
//             }
//         }
//     }
//
//     func refreshDevices() {
//         startAutoDetect()
//     }
//
//     func rebootToBootloader(serial: String) {
//         statusMessage = "Rebooting to bootloader…"
//         Task {
//             let result = await Self.runADBCommand(["-s", serial, "reboot", "bootloader"])
//             switch result {
//             case .success:
//                 await MainActor.run {
//                     self.statusMessage = "Reboot command sent. Waiting for device…"
//                     // Optionally, start a new detection cycle after a short delay
//                     self.startAutoDetect()
//                 }
//             case .failure(let error):
//                 await MainActor.run {
//                     self.statusMessage = "Error rebooting: \(error.localizedDescription)"
//                 }
//             }
//         }
//     }
//
//     private static func runADBDevices() async -> Result<String, Error> {
//         await withCheckedContinuation { continuation in
//             let process = Process()
//             // Try to locate adb in PATH using /bin/zsh -lc "which adb && adb devices"
//             // This allows users with adb installed via Homebrew/Android SDK.
//             process.executableURL = URL(fileURLWithPath: "/bin/zsh")
//             process.arguments = ["-lc", "adb devices"]
//
//             let pipe = Pipe()
//             process.standardOutput = pipe
//             process.standardError = pipe
//
//             do {
//                 try process.run()
//             } catch {
//                 continuation.resume(returning: .failure(error))
//                 return
//             }
//
//             process.terminationHandler = { _ in
//                 let data = pipe.fileHandleForReading.readDataToEndOfFile()
//                 let output = String(data: data, encoding: .utf8) ?? ""
//                 continuation.resume(returning: .success(output))
//             }
//         }
//     }
//
//     private static func runADBCommand(_ args: [String]) async -> Result<Void, Error> {
//         await withCheckedContinuation { continuation in
//             let process = Process()
//             process.executableURL = URL(fileURLWithPath: "/bin/zsh")
//             // Build a safe command string: adb followed by joined arguments, all properly escaped
//             let escaped = args.map { "'" + $0.replacingOccurrences(of: "'", with: "'\\''") + "'" }.joined(separator: " ")
//             process.arguments = ["-lc", "adb \(escaped)"]
//
//             let pipe = Pipe()
//             process.standardOutput = pipe
//             process.standardError = pipe
//
//             do {
//                 try process.run()
//             } catch {
//                 continuation.resume(returning: .failure(error))
//                 return
//             }
//
//             process.terminationHandler = { _ in
//                 // We don't need the output here; success is based on exit status
//                 if process.terminationStatus == 0 {
//                     continuation.resume(returning: .success(()))
//                 } else {
//                     let data = pipe.fileHandleForReading.readDataToEndOfFile()
//                     let output = String(data: data, encoding: .utf8) ?? "Unknown error"
//                     continuation.resume(returning: .failure(NSError(domain: "ADB", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: output])))
//                 }
//             }
//         }
//     }
//
//     private static func parseADBDevicesOutput(_ output: String) -> [String] {
//         // Expected format:
//         // List of devices attached
//         // emulator-5554\tdevice
//         // XYZ123\tdevice
//         //
//         // We collect lines that end with "\tdevice" or "\tunauthorized" etc., and return the serial before the tab.
//         let lines = output
//             .split(separator: "\n")
//             .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
//             .filter { !$0.isEmpty }
//
//         var serials: [String] = []
//         for line in lines {
//             if line.lowercased().hasPrefix("list of devices attached") { continue }
//             // Typical states: device, unauthorized, offline
//             if let tabRange = line.range(of: "\t") {
//                 let serial = String(line[..<tabRange.lowerBound])
//                 if !serial.isEmpty { serials.append(serial) }
//             } else if line.contains("\t") == false && line.contains("device") == false && !line.contains("daemon") {
//                 // Some adb versions might print just serials on separate lines (rare). Try to capture plausible serials.
//                 let candidate = line.components(separatedBy: .whitespaces).first ?? line
//                 if !candidate.isEmpty && candidate.lowercased() != "list" { serials.append(candidate) }
//             }
//         }
//         return Array(Set(serials)).sorted()
//     }
// }
//
// #Preview {
//     FlashROMView()
//         .environmentObject(AppNavigation())
// }
