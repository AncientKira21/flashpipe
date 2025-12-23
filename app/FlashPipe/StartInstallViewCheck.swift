//
//  StartInstallViewCheck.swift
//  FlashPipe
//
//  Created by Ancient Kira on 12/5/25.
//

import SwiftUI

struct StartInstallViewCheck: View {
    @EnvironmentObject var installState: FPInstallState
    @Binding var showSidebar: Bool

    @State private var isInstalling: Bool = false
    @State private var installLog: String = ""
    @State private var showPermissionSheet: Bool = false
    @State private var finishedCheck: Bool = false

    init(showSidebar: Binding<Bool>) {
        self._showSidebar = showSidebar
    }

    var body: some View {
        Group {
            if showSidebar {
                SidebarView()
            } else {
                HStack(spacing: 0) {
                    FakeSidebarView()
                        .frame(width: 220)

                    VStack(spacing: 20) {
                        ProgressView()
                        Text(isInstalling ? "Installing Tools…" : "Checking Tools…")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .onAppear { runCheck() }
        .sheet(isPresented: $showPermissionSheet) {
            VStack(spacing: 16) {
                Text("Install Failed")
                    .font(.title3)
                    .bold()
                ScrollView {
                    Text(installLog)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .frame(height: 200)
                Button("Close") {
                    showPermissionSheet = false
                    showSidebar = true
                    NotificationCenter.default.post(name: Notification.Name("FlashPipe_OpenSidebar_WithFailure"), object: nil)
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
            .frame(width: 450, height: 350)
        }
    }

    private func runCheck() {
        DispatchQueue.global(qos: .userInitiated).async {
            let missingBefore = checkMissing()

            DispatchQueue.main.async {
                if missingBefore {
                    isInstalling = true
                    installState.toolsReady = false
                    installTools()
                } else {
                    installState.toolsReady = true
                    showSidebar = true
                }
            }
        }
    }

    private func checkMissing() -> Bool {
        let fm = FileManager.default
        let bins = ["/usr/local/bin", "/opt/homebrew/bin"]

        let required = ["adb","etc1tool","fastboot","hprof-conv","make_f2fs","make_f2fs_casefold","mke2fs","sqlite3","heimdall"]

        for tool in required {
            var found = false
            for bin in bins {
                if fm.fileExists(atPath: "\(bin)/\(tool)") {
                    found = true
                    break
                }
            }
            if !found { return true }
        }
        print("All tools found — toolsReady = true")
        return false
    }

    private func installTools() {
        let macosPath = Bundle.main.bundlePath + "/Contents/MacOS"
        let script = """
set macPath to "\(macosPath)"
do shell script "mkdir -p /usr/local/bin; find " & quoted form of macPath & " -type f ! -name 'FlashPipe*' -exec cp -f {} /usr/local/bin/ \\\\; ; chmod 777 /usr/local/bin/*; xattr -d com.apple.quarantine /usr/local/bin/* || true" with administrator privileges
"""

        installLog = "Starting installation…\n"

        DispatchQueue.global(qos: .userInitiated).async {
            let result = runAppleScript(script)

            DispatchQueue.main.async {
                installLog += result
                let missingAfter = checkMissing()
                if missingAfter {
                    installState.toolsReady = false
                    showPermissionSheet = true
                } else {
                    installState.toolsReady = true
                    showSidebar = true
                    showPermissionSheet = false
                }
                isInstalling = false
            }
        }
    }

    private func runAppleScript(_ script: String) -> String {
        let process = Process()
        process.launchPath = "/usr/bin/osascript"
        process.arguments = ["-e", script]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do { try process.run() } catch {
            return "Failed to execute AppleScript.\n\(error)"
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? "Unknown result."
    }
}

struct FakeSidebarView: View {
    var body: some View {
        NavigationSplitView {
            List {
                fakeRow(.home)
                fakeRow(.adbDevices)
                fakeRow(.flashRom)
                fakeRow(.fastboot)
                fakeRow(.unlockBoot)
                fakeRow(.settings)
//                fakeRow(.credits)
//                fakeRow(.about)
            }
            .navigationTitle("Sidebar")
        } detail: {
            EmptyView()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func fakeRow(_ item: SidebarItem) -> some View {
        HStack(spacing: 10) {
            Image(systemName: item.systemImage)
            Text(item.title)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            // Do NOTHING — this is a fake sidebar
        }
}
