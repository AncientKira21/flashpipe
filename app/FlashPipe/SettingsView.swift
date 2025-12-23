//
//  SettingsView.swift
//  FlashPipe
//
//  Created by Ancient Kira on 11/25/25.
//

import SwiftUI

struct SettingsView: View {
    @Binding var selection: SidebarItem?
    @EnvironmentObject private var installState: FPInstallState
    @AppStorage("checkForUpdates") private var checkForUpdates = true
    @AppStorage("logLevel") private var logLevel = "Normal"
    @AppStorage("autoDetect") private var autoDetect = true
    @State private var showingInstallAlert = false
    @State private var showInstallPopup = false
    @State private var installing = true
    @State private var alertMessage: AlertMessage? = nil
    @State private var installLog: String = ""

    var body: some View {
        VStack {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Check for updates automatically", isOn: $checkForUpdates)
                Toggle("Auto-detect devices on launch", isOn: $autoDetect)
            }
            .frame(maxWidth: 450)
            .padding(.top, 40)

            Spacer().frame(height: 40)

            Button("About") {
                withAnimation(.easeInOut) { selection = .about }
            }
            .frame(maxWidth: 450)
            .buttonStyle(.bordered)

            Button("Credits") {
                withAnimation(.easeInOut) { selection = .credits }
            }
            .frame(maxWidth: 450)
            .buttonStyle(.bordered)

            Spacer()

            Button("Install Tools") {
                startInstallation()
            }
            .frame(maxWidth: 450)
            .buttonStyle(.bordered)
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity)
        .alert(item: $alertMessage) { alertMsg in
            Alert(title: Text(""), message: Text(alertMsg.message), dismissButton: .default(Text("OK")) {
                alertMessage = nil
                installing = false
            })
        }
        .sheet(isPresented: $showInstallPopup) {
            VStack(spacing: 20) {
                Text("Installation failed")
                    .font(.headline)
                ScrollView {
                    Text(installLog)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                Button("OK") {
                    showInstallPopup = false
                    installing = false
                }
            }
            .padding()
            .frame(maxWidth: 300)
        }
    }

    private func startInstallation() {
        installing = true
        showInstallPopup = false
        alertMessage = nil
        installLog = ""
        guard let execURL = Bundle.main.executableURL else {
            DispatchQueue.main.async {
                installing = false
                alertMessage = AlertMessage(message: "Failed to locate executable.")
            }
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            var logLines: [String] = []
            func append(_ s: String) { logLines.append(s) }

            let macosDir = execURL.deletingLastPathComponent()
            let execName = execURL.lastPathComponent
            append("MacOS dir: \(macosDir.path)")
            append("Executable: \(execName)")

            // List regular files in MacOS dir
            let fm = FileManager.default
            let contents: [URL]
            do {
                contents = try fm.contentsOfDirectory(at: macosDir, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
            } catch {
                contents = []
                append("Failed to list MacOS dir: \(error.localizedDescription)")
            }

            var anySystemSucceeded = false

            // Build list of tool files (skip the main executable)
            let toolFiles = contents.filter { url in
                url.lastPathComponent != execName &&
                ((try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true)
            }

            append("Found \(toolFiles.count) tools to install")

            // Build AppleScript argument list
            let fileList = toolFiles.map { $0.path }.joined(separator: " ")
            let script = """
            do shell script "
                mkdir -p /usr/local/bin &&
                for f in \(fileList); do
                    base=$(basename \\"$f\\");
                    cp -f \\"$f\\" /usr/local/bin/$base;
                done &&
                chmod 755 /usr/local/bin/* &&
                xattr -d com.apple.quarantine /usr/local/bin/* 2>/dev/null || true
            " with administrator privileges
            """

            let osa = Process()
            osa.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            osa.arguments = ["-e", script]

            let pipe = Pipe()
            osa.standardOutput = pipe
            osa.standardError = pipe

            do {
                try osa.run()
                osa.waitUntilExit()
                if osa.terminationStatus == 0 {
                    append("System installation succeeded")
                    anySystemSucceeded = true
                } else {
                    append("System installation failed")
                }
            } catch {
                append("Failed to invoke osascript: \(error.localizedDescription)")
            }

            let finalLog = logLines.joined(separator: "\n")

            DispatchQueue.main.async {
                installing = false
                if anySystemSucceeded {
                    installState.toolsReady = true
                    alertMessage = AlertMessage(message: "Tools installed to system locations.")
                } else {
                    installLog = finalLog
                    showInstallPopup = true
                }
            }
        }
    }
}

private struct AlertMessage: Identifiable {
    let id = UUID()
    let message: String
}

struct AboutView: View {
    @Binding var selection: SidebarItem?

    var body: some View {

        let iconName: String = {
            if #available(macOS 26, *) {
                return "NewIcon.icon"
            } else {
                return "AppIcon.icns"
            }
        }()

        let image: NSImage = {
            if let url = Bundle.main.url(forResource: iconName.replacingOccurrences(of: ".icon", with: "").replacingOccurrences(of: ".icns", with: ""), withExtension: iconName.hasSuffix(".icon") ? "icon" : "icns"),
               let img = NSImage(contentsOf: url) {
                return img
            }
            return NSImage(
                systemSymbolName: "exclamationmark.triangle.fill",
                accessibilityDescription: nil
            )!
        }()

        VStack(spacing: 14) {

            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 86, height: 86)
                .cornerRadius(20)
                .padding(.top, 40)

            Text("FlashPipe")
                .font(.title2)
                .fontWeight(.semibold)

            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
            let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
            Text("Version \(version) (\(build))")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()
        }
        .frame(maxWidth: 450)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    withAnimation(.easeInOut) { selection = .settings }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
        }
    }
}

struct CreditsView: View {
    @Binding var selection: SidebarItem?

    var body: some View {
        let iconName: String = {
            if #available(macOS 26, *) {
                return "NewIcon.icon"
            } else {
                return "AppIcon.icns"
            }
        }()

        let image: NSImage = {
            if let url = Bundle.main.url(forResource: iconName.replacingOccurrences(of: ".icon", with: "").replacingOccurrences(of: ".icns", with: ""), withExtension: iconName.hasSuffix(".icon") ? "icon" : "icns"),
               let img = NSImage(contentsOf: url) {
                return img
            }
            return NSImage(
                systemSymbolName: "exclamationmark.triangle.fill",
                accessibilityDescription: nil
            )!
        }()

        VStack {

            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 86, height: 86)
                .cornerRadius(20)
                .padding(.top, 40)

            Text("FlashPipe")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Credits")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()

            ScrollView {
                Text(verbatim: """
Platform Tools (ADB & Fastboot)

This application utilizes the Android Debug Bridge (ADB) and Fastboot command-line tools. These tools are part of the Android Open Source Project (AOSP).

Iconography & Images

The application icon was designed using a modified glyph sourced from the Google Material Symbols library. Material Symbols are provided by Google under the Apache License Version 2.0.
The Google Pixel 10 frame in Home is made by Mliu92, CC BY-SA 4.0 <https://creativecommons.org/licenses/by-sa/4.0>, via Wikimedia Commons
The Android robot is reproduced or modified from work created and shared by Google and used according to terms described in the Creative Commons 3.0 Attribution License.
The Android 16 logo in Home is made by Google, CC BY 2.5 <https://creativecommons.org/licenses/by/2.5>, via Wikimedia Commons

Trademarks

Android is a trademark of Google LLC.

Developer & Contact

FlashPipe
Ancient Kira
XDA: https://xdaforums.com/m/ancientkira21.13293538/
""")
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
            .frame(maxWidth: 450)
            .transition(.slide)
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    withAnimation(.easeInOut) { selection = .settings }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
        }
    }
}
