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
    @State private var sidebarSelection: SidebarItem? = nil

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
        let required = ["adb", "etc1tool", "fastboot", "hprof-conv", "make_f2fs", "make_f2fs_casefold", "mke2fs", "sqlite3"]
//        let required = ["adb", "etc1tool", "fastboot", "hprof-conv", "make_f2fs", "make_f2fs_casefold", "mke2fs", "sqlite3", "heimdall"]

        for tool in required {
            var foundLocally = false
            for bin in bins {
                let fullPath = "\(bin)/\(tool)"
                if fm.fileExists(atPath: fullPath) {
                    // Ensure it is actually executable
                    if fm.isExecutableFile(atPath: fullPath) {
                        foundLocally = true
                        break
                    }
                }
            }
            
            if !foundLocally {
                print("⚠️ Missing tool: \(tool)")
                return true // Found a missing tool, return true immediately
            }
        }
        
        print("✅ All tools verified and executable!")
        return false
    }

    private func installTools() {
            let macosPath = Bundle.main.bundlePath + "/Contents/MacOS"
            
            // List of all tools to be moved
            let toolsToInstall = ["adb", "etc1tool", "fastboot", "hprof-conv", "make_f2fs", "make_f2fs_casefold", "mke2fs", "sqlite3"]
//            let toolsToInstall = ["adb", "etc1tool", "fastboot", "hprof-conv", "make_f2fs", "make_f2fs_casefold", "mke2fs", "sqlite3", "heimdall"]
            let toolsJoined = toolsToInstall.joined(separator: " ")

            let script = """
            set macPath to "\(macosPath)"
            do shell script "mkdir -p /usr/local/bin; \
            cd " & quoted form of macPath & " && \
            cp -af \(toolsJoined) /usr/local/bin/ && \
            chmod 755 /usr/local/bin/* && \
            xattr -cr /usr/local/bin/adb /usr/local/bin/fastboot /usr/local/bin/heimdall || true; \
            codesign -f -s - /usr/local/bin/adb" with administrator privileges
            """

            installLog = "Installing tools and fixing adb signature…\n"
            isInstalling = true

            DispatchQueue.global(qos: .userInitiated).async {
                let result = runAppleScript(script)

                DispatchQueue.main.async {
                    installLog += result
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        let missingAfter = checkMissing()
                        isInstalling = false

                        if missingAfter {
                            installState.toolsReady = false
                            showPermissionSheet = true
                            installLog += "\n❌ Error: Tool verification failed.\n"
                        } else {
                            installState.toolsReady = true
                            showSidebar = true
                            showPermissionSheet = false
                        }
                    }
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
    // Local enum to back the fake sidebar items
    private enum SidebarItem: Hashable, CaseIterable {
        case home
        case adbDevices
        case flashRom
        case fastboot
        case unlockBoot
        case settings

        var title: String {
            switch self {
            case .home: return "Home"
            case .adbDevices: return "ADB Devices"
            case .flashRom: return "Flash ROM"
            case .fastboot: return "Fastboot"
            case .unlockBoot: return "Unlock Bootloader"
            case .settings: return "Settings"
            }
        }

        var systemImage: String {
            switch self {
            case .home: return "house"
            case .adbDevices: return "iphone"
            case .flashRom: return "bolt.fill"
            case .fastboot: return "speedometer"
            case .unlockBoot: return "lock.open"
            case .settings: return "gear"
            }
        }
    }

    @State private var selection: SidebarItem? = .home

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(SidebarItem.allCases, id: \.self) { item in
                    fakeRow(item).tag(item)
                }
            }
            .navigationTitle("Sidebar")
        } detail: {
            EmptyView()
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
            // Do NOTHING — this is a fake sidebar, but keep selection updated
            selection = item
        }
    }
}

