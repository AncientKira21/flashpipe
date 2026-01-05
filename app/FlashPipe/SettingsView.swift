//
//  SettingsView.swift
//  FlashPipe
//
//  Created by Ancient Kira on 11/25/25.
//

import SwiftUI
import AppKit

struct SettingsView: View {
//    @Binding var selection: SidebarItem?
    @EnvironmentObject private var installState: FPInstallState
    @AppStorage("checkForUpdates") private var checkForUpdates = true
    @AppStorage("logLevel") private var logLevel = "Normal"
    @AppStorage("autoDetect") private var autoDetect = true
    @State private var showingInstallAlert = false
    @State private var showInstallPopup = false
    @State private var installing = true
    @State private var alertMessage: AlertMessage? = nil
    @State private var installLog: String = ""
    @State private var navigateToAbout = false
    
    private var isMacOS26OrNewer: Bool {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return v.majorVersion >= 26
    }
    
    var body: some View {
        VStack {
            NavigationLink() {
                AboutView()
                    .transition(.move(edge: .leading))
            } label: {
                EmptyView()
            }
            .hidden()

            VStack(alignment: .leading, spacing: 12) {
            }
            .frame(maxWidth: 450)
            .padding(.top, 40)
            
            Spacer().frame(height: 40)
            
            NavigationLink {
                AboutView()
                    .transition(.move(edge: .leading))
            } label: {
                if isMacOS26OrNewer {
                    Label("About", systemImage: "info.circle")
                } else {
                    Text("About")
                }
            }
            .frame(maxWidth: 450)
            .buttonStyle(.bordered)
            
            NavigationLink {
                CreditsView()
                    .transition(.move(edge: .leading))
            } label: {
                if isMacOS26OrNewer {
                    Label("Credits", systemImage: "list.bullet")
                } else {
                    Text("Credits")
                }
            }
            .frame(maxWidth: 450)
            .buttonStyle(.bordered)
            
            NavigationLink {
                LanguageView()
                    .transition(.move(edge: .leading))
            } label: {
                if isMacOS26OrNewer {
                    Label("Language", systemImage: "globe")
                } else {
                    Text("Language")
                }
            }
            .frame(maxWidth: 450)
            .buttonStyle(.bordered)
            
            Spacer()
            
            Button("Install Tools") {
                print("[SettingsView] Install Tools tapped")
                startInstallation()
            }
            .frame(maxWidth: 450)
            .buttonStyle(.bordered)
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity)
        .onAppear { print("[SettingsView] onAppear; toolsReady=\(installState.toolsReady)") }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("FlashPipe_Settings_ShowAbout"))) { _ in
            navigateToAbout = true
        }
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
        print("[SettingsView] startInstallation")
        installing = true
        showInstallPopup = false
        alertMessage = nil
        installLog = ""
        
        guard let execURL = Bundle.main.executableURL else {
            print("[SettingsView] Failed to locate executable")
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
//            let execName = execURL.lastPathComponent
            
            let fm = FileManager.default
            let contents: [URL]
            do {
                contents = try fm.contentsOfDirectory(at: macosDir, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
            } catch {
                contents = []
                append("Failed to list MacOS dir: \(error.localizedDescription)")
            }
            
            // Filter for specific tools to ensure consistency with the check function
            let requiredNames = ["adb", "etc1tool", "fastboot", "hprof-conv", "make_f2fs", "make_f2fs_casefold", "mke2fs", "sqlite3", "heimdall"]
            let toolFiles = contents.filter { requiredNames.contains($0.lastPathComponent) }
            
            append("Found \(toolFiles.count) tools to install")
            
            // Escape paths for shell
            let fileList = toolFiles.map { "'\($0.path)'" }.joined(separator: " ")
            
            // Match the robust StartInstallViewCheck logic
            let script = """
            do shell script "
                mkdir -p /usr/local/bin &&
                for f in \(fileList); do
                    base=$(basename \\"$f\\");
                    cp -af \\"$f\\" /usr/local/bin/\\"$base\\";
                done &&
                chmod 755 /usr/local/bin/* &&
                xattr -cr /usr/local/bin/adb /usr/local/bin/fastboot /usr/local/bin/heimdall || true &&
                codesign -f -s - /usr/local/bin/adb
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
                    // Perform a final verification check just like StartInstallViewCheck does
                    // You can call your checkMissing() helper here if accessible
                    DispatchQueue.main.async {
                        installing = false
                        installState.toolsReady = true
                        alertMessage = AlertMessage(message: "Tools installed.")
                    }
                } else {
                    let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
                    let errorStr = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                    append("Error: \(errorStr)")
                    
                    DispatchQueue.main.async {
                        installing = false
                        installLog = logLines.joined(separator: "\n")
                        showInstallPopup = true
                    }
                }
            } catch {
                append("Execution error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    installing = false
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

private func loadReliableAppIcon() -> Image {
    print("[SettingsView] loadReliableAppIcon called")
    // Prefer the system app icon when available
    if let appIcon = NSApplication.shared.applicationIconImage, appIcon.isValid {
        print("[SettingsView] Using NSApplication icon")
        return Image(nsImage: appIcon)
    }

    // Try explicit NewIcon.icns first (works on macOS 26 when .icon may fail)
    if let icnsURL = Bundle.main.url(forResource: "NewIcon", withExtension: "icns"),
       let nsGood = NSImage(contentsOf: icnsURL), nsGood.isValid {
        print("[SettingsView] Loaded NewIcon.icns")
        return Image(nsImage: nsGood)
    }

    // Try asset name fallbacks
    if let ns = NSImage(named: "NewIcon") {
        print("[SettingsView] Using asset 'NewIcon'")
        return Image(nsImage: ns)
    }
    if NSImage(named: "AppIcon") != nil {
        print("[SettingsView] Using asset 'AppIcon'")
        return Image("AppIcon")
    }

    // Try CFBundleIconFile
    if let iconFile = Bundle.main.infoDictionary?["CFBundleIconFile"] as? String {
        print("[SettingsView] Using CFBundleIconFile: \(iconFile)")
        let iconNameWithExt: String = iconFile.contains(".") ? iconFile : iconFile + ".icns"
        let baseName = (iconNameWithExt as NSString).deletingPathExtension
        let ext = (iconNameWithExt as NSString).pathExtension
        if let url = Bundle.main.url(forResource: baseName, withExtension: ext),
           let nsImage = NSImage(contentsOf: url), nsImage.isValid {
            return Image(nsImage: nsImage)
        }
    }

    // Final fallback
    print("[SettingsView] Falling back to warning symbol")
    return Image(systemName: "exclamationmark.triangle.fill")
}

struct AboutView: View {
//    @Binding var selection: SidebarItem?
    @Environment(\.dismiss) private var dismiss

    var body: some View {

        let appIcon: Image = loadAppIcon()

        VStack(spacing: 14) {

            appIcon
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
        .transition(.move(edge: .trailing))
        .frame(maxWidth: 450)
        .onAppear { print("[AboutView] onAppear") }
    }

    private func loadAppIcon() -> Image {
        return loadReliableAppIcon()
    }
}

struct LanguageView: View {
//    @Binding var selection: SidebarItem?
    @State private var selectedLanguage: String = Locale.preferredLanguages.first.flatMap { Locale(identifier: $0).language.languageCode?.identifier } ?? Locale.current.language.languageCode?.identifier ?? "en"
    @State private var showRestartAlert = false
    @Environment(\.dismiss) private var dismiss
    
    private func normalizeLanguageIdentifier(_ identifier: String) -> String {
        if let base = Locale(identifier: identifier).language.languageCode?.identifier {
            return base
        }
        // Fallback: split by '-' or '_' and take the first component
        if let first = identifier.split(whereSeparator: { $0 == "-" || $0 == "_" }).first {
            return String(first)
        }
        return identifier
    }
    
    private func currentPerAppLanguage() -> String? {
        // System Settings stores per-app language in the app's UserDefaults under key "AppleLanguages"
        // It's an array of identifiers like ["en"], ["fr"], etc.
        if let langs = UserDefaults.standard.array(forKey: "AppleLanguages") as? [String], let first = langs.first, !first.isEmpty {
            print("[LanguageView] Found per-app AppleLanguages: \(langs). Using first: \(first)")
            return normalizeLanguageIdentifier(first)
        }
        print("[LanguageView] No per-app AppleLanguages set; falling back to system preferred languages")
        return nil
    }
    
    private func setPerAppLanguage(_ code: String) {
        // Set the per-app language list to the selected code; System Settings expects an array
        let base = normalizeLanguageIdentifier(code)
        UserDefaults.standard.set([base], forKey: "AppleLanguages")
        UserDefaults.standard.synchronize()
        print("[LanguageView] Setting per-app AppleLanguages to: [\(base)]")
    }
    
    var body: some View {
        let supported = Bundle.main.object(forInfoDictionaryKey: "CFBundleLocalizations") as? [String] ?? []
        let displayNames = supported.map { Locale.current.localizedString(forLanguageCode: $0) ?? $0 }
        
        VStack(alignment: .leading, spacing: 12) {
            Text("Supported Languages")
                .font(.title2)
                .fontWeight(.semibold)
                .padding(.top, 30)
            
            List {
                ForEach(Array(zip(supported, displayNames)), id: \.0) { code, name in
                    HStack {
                        Text(name)
                        Spacer()
                        if normalizeLanguageIdentifier(selectedLanguage) == normalizeLanguageIdentifier(code) {
                            Image(systemName: "checkmark")
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if selectedLanguage != code {
                            selectedLanguage = code
                            print("[LanguageView] User selected language code: \(code)")
                            // Persist to System Settings (per-app language)
                            setPerAppLanguage(code)
                            // Ask for restart to apply new localization
                            showRestartAlert = true
                        }
                    }
                }
            }
            .frame(maxWidth: 450)
        }
        .transition(.move(edge: .trailing))
        .frame(maxWidth: .infinity, alignment: .top)
        .alert("Language changed", isPresented: $showRestartAlert) {
            Button("OK") { restartApp() }
        } message: {
            Text("App will restart and use your preferred language.")
        }
        .onAppear {
            print("[LanguageView] onAppear")
            let supported = Bundle.main.object(forInfoDictionaryKey: "CFBundleLocalizations") as? [String] ?? []
            let displayNames = supported.map { Locale.current.localizedString(forLanguageCode: $0) ?? $0 }
            print("[LanguageView] Supported codes: \(supported)")
            print("[LanguageView] Display names: \(displayNames)")
            if let current = currentPerAppLanguage() {
                selectedLanguage = normalizeLanguageIdentifier(current)
                print("[LanguageView] onAppear: Using per-app language \(current)")
            } else {
                print("[LanguageView] onAppear: Using initial selectedLanguage fallback: \(selectedLanguage)")
            }
        }
    }
    
    private func restartApp() {
        print("[LanguageView] restartApp requested")
        let path = Bundle.main.bundlePath
        
        // Fully detach relaunch process
        let script = """
        (sleep 0.3; /usr/bin/open "\(path)") &
        """
        
        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", script]
        task.launch()
        
        print("[LanguageView] Terminating for restart…")
        // Terminate current instance
        NSApplication.shared.terminate(nil)
    }
}

struct CreditsView: View {
//    @Binding var selection: SidebarItem?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let appIcon: Image = loadAppIcon()

        VStack {

            appIcon
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
        }
        .onAppear { print("[CreditsView] onAppear") }
    }

    private func loadAppIcon() -> Image {
        return loadReliableAppIcon()
    }
}

