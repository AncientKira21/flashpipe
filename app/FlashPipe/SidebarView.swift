//
//  SidebarView.swift
//  FlashPipe
//
//  Created by Ancient Kira on 11/23/25.
//

import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var nav: AppNavigation
    @EnvironmentObject private var installState: FPInstallState

    @ViewBuilder
    private var detailContent: some View {
        switch nav.selection {
        case .home:
            ContentView()
        case .adbDevices:
            ADBView()
        case .fastboot:
            Fastboot1View()
        case .flashRom:
            FlashROM1View()
        case .unlockBoot:
            ContentPlaceholder(title: "Unlock Bootloader")
        case .settings:
            SettingsView(selection: $nav.selection)
        case .credits:
            CreditsView(selection: $nav.selection)
        case .about:
            AboutView(selection: $nav.selection)
        case .none:
            EmptyView()
        }
    }

    var body: some View {
        if #available(macOS 13.0, *) {
            NavigationSplitView {
                SidebarList(selection: $nav.selection) { item in
                    nav.selection = item
                }
            } detail: {
                detailContent
                    .navigationTitle(nav.selection?.title ?? "Details")
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("FlashPipe_OpenSidebar_WithFailure"))) { _ in
                installState.toolsReady = false
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("FlashPipe_OpenSidebar"))) { _ in
                installState.toolsReady = true
            }
        } else {
            NavigationView {
                SidebarList(selection: $nav.selection) { item in
                    nav.selection = item
                }
                .listStyle(.sidebar)
                .navigationTitle("Sidebar")

                destinationView(for: nav.selection)
                    .navigationTitle(nav.selection?.title ?? "Details")
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("FlashPipe_OpenSidebar_WithFailure"))) { _ in
                installState.toolsReady = false
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("FlashPipe_OpenSidebar"))) { _ in
                installState.toolsReady = true
            }
        }
    }

    private struct SidebarRow: View {
        let item: SidebarItem
        var body: some View {
            Label(item.title, systemImage: item.systemImage)
                .tag(item)
        }
    }

    private struct SidebarList: View {
        @Binding var selection: SidebarItem?
        let onTap: (SidebarItem) -> Void
        @EnvironmentObject private var installState: FPInstallState
        @State private var lastAllowedSelection: SidebarItem? = .home

        init(selection: Binding<SidebarItem?>, onTap: @escaping (SidebarItem) -> Void) {
            self._selection = selection
            self.onTap = onTap
        }

        var body: some View {
            List(SidebarItem.visibleCases, selection: $selection) { item in
                SidebarRow(item: item)
                    .disabled(!installState.toolsReady && !(item == .home || item == .settings || item == .about || item == .credits))
                    .opacity((!installState.toolsReady && !(item == .home || item == .settings || item == .about || item == .credits)) ? 0.3 : 1.0)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if installState.toolsReady || (item == .home || item == .settings || item == .about || item == .credits) {
                            lastAllowedSelection = item
                            onTap(item)
                        }
                    }
                    .onChange(of: selection) { oldValue, newValue in
                        if let item = newValue {
                            if installState.toolsReady {
                                lastAllowedSelection = item
                            } else {
                                if !(item == .home || item == .settings || item == .about || item == .credits) {
                                    selection = lastAllowedSelection
                                } else {
                                    lastAllowedSelection = item
                                }
                            }
                        }
                    }
            }
        }
    }

    @ViewBuilder
    private func destinationView(for selection: SidebarItem?) -> some View {
        switch selection {
        case .home:
            ContentView()
        case .adbDevices:
            ADBView()
        case .fastboot:
            Fastboot1View()
        case .flashRom:
            FlashROM1View()
        case .unlockBoot:
            ContentPlaceholder(title: "Unlock Bootloader")
        case .settings:
            SettingsView(selection: $nav.selection)
        case .credits:
            CreditsView(selection: $nav.selection)
        case .about:
            AboutView(selection: $nav.selection)
        case .none:
            EmptyView()
        }
    }
}

private struct ContentPlaceholder: View {
    let title: String
    var body: some View {
        VStack(spacing: 12) {
            Image("Android_Error")
                .resizable()
                .scaledToFit()
                .frame(width: 80, height: 80)
            Text("Coming Soon!")
                .font(.title2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

enum SidebarItem: String, Identifiable {
    case home
    case adbDevices // Start (ADB detection)
    case flashRom // New: Flash ROM (Sideload)
    case fastboot
    case unlockBoot
    case settings
    case credits
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .adbDevices: return "Start"
        case .flashRom: return "Flash ROM" // New Title
        case .fastboot: return "Fastboot"
        case .unlockBoot: return "Unlock Bootloader"
        case .settings: return "Settings"
        case .credits: return "Credits"
        case .about: return "About"
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "house"
        case .adbDevices: return "cable.connector.horizontal"
        case .flashRom: return "bolt" // New Icon
        case .fastboot: return "wrench"
        case .unlockBoot: return "lock.open"
        case .settings: return "gear"
        case .credits: return "star"
        case .about: return "info.circle"
        }
    }

    static var visibleCases: [SidebarItem] {
        [.home, .adbDevices, .flashRom, .fastboot, .unlockBoot, .settings]
    }
}

#Preview {
    SidebarView()
        .environmentObject(AppNavigation())
        .environmentObject(FPInstallState(toolsReady: true))
}
