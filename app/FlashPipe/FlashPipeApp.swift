//
//  FlashPipeApp.swift
//  FlashPipe
//
//  Created by Ancient Kira on 10/13/25.
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

@main
struct FlashPipeApp: App {
    init() {
        setenv("OS_ACTIVITY_MODE", "default", 1)
    }
    @StateObject private var nav = AppNavigation()
    @StateObject private var devices = ADBDevicesViewModel()
    @StateObject private var installState = FPInstallState(toolsReady: true)
    @State private var showSidebar: Bool = false

    private var isMacOS26OrNewer: Bool {
        #if os(macOS)
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return v.majorVersion >= 26
        #else
        return false
        #endif
    }

    var body: some Scene {
        WindowGroup {
            StartInstallViewCheck(showSidebar: $showSidebar)
                .environmentObject(nav)
                .environmentObject(installState)
                .environmentObject(devices)
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button(action: { nav.selection = .about }) {
                    if isMacOS26OrNewer {
                        Label("About FlashPipe", systemImage: "info.circle")
                    } else {
                        Text("About FlashPipe")
                    }
                }
            }
            CommandGroup(after: .appSettings) {
                Button(action: { nav.selection = .settings }) {
                    if isMacOS26OrNewer {
                        Label("Settings…", systemImage: "gearshape")
                    } else {
                        Text("Settings…")
                    }
                }
                .keyboardShortcut(",", modifiers: [.command])
            }
            CommandMenu("Flash") {
                Button(action: { nav.selection = .fastboot }) {
                    if isMacOS26OrNewer {
                        Label("Recovery", systemImage: "lifepreserver")
                    } else {
                        Text("Recovery")
                    }
                }
                Button(action: { nav.selection = .fastboot }) {
                    if isMacOS26OrNewer {
                        Label("Logo", systemImage: "app")
                    } else {
                        Text("Logo")
                    }
                }
                Button(action: { nav.selection = .fastboot }) {
                    if isMacOS26OrNewer {
                        Label("GSI", systemImage: "square.stack.3d.up")
                    } else {
                        Text("GSI")
                    }
                }
                Divider()
                Button(action: { nav.selection = .flashRom }) {
                    if isMacOS26OrNewer {
                        Label("ROM", systemImage: "externaldrive")
                    } else {
                        Text("ROM")
                    }
                }
            }
        }
    }
}
