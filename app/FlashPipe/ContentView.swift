//
//  ContentView.swift
//  FlashPipe
//
//  Created by Ancient Kira on 10/13/25.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var nav: AppNavigation
    @EnvironmentObject private var installState: FPInstallState

    var body: some View {
        GeometryReader { proxy in
            // Dynamic size with sensible bounds
            let totalWidth = proxy.size.width
            let interItemSpacing: CGFloat = 24
            let maxContentWidth: CGFloat = 800 // cap total content width so it stays centered
            let rawEffectiveWidth = min(totalWidth.isFinite ? totalWidth - 40 : 0, maxContentWidth)
            let effectiveWidth = max(rawEffectiveWidth, 0)
            let proposedColumn = (effectiveWidth - interItemSpacing) / 2
            let columnWidth = max(min(proposedColumn.isFinite ? proposedColumn : 0, 300), 120)

            ZStack {
                VStack(spacing: 24) {
                    HStack(alignment: .top, spacing: interItemSpacing) {
                        VStack(spacing: 8) {
                            Image("WorkingDevice")
                                .resizable()
                                .scaledToFit()
                                .frame(width: max(columnWidth, 0), height: max(columnWidth, 0))
                                .cornerRadius(12)
                            Text("My device is running, but I want to MOD it")
                                .font(.headline)
                            Button {
                                nav.selection = .adbDevices
                            } label: {
                                Label("Start", systemImage: "bolt")
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!installState.toolsReady)
                            .opacity(installState.toolsReady ? 1 : 0.3)
                        }

                        VStack(spacing: 8) {
                            Image("FastbootDevice")
                                .resizable()
                                .scaledToFit()
                                .frame(width: max(columnWidth, 0), height: max(columnWidth, 0))
                                .cornerRadius(12)
                            Text("My device is bricked, and I want to unbrick it")
                                .font(.headline)
                            Button {
                                nav.selection = .fastboot
                            } label: {
                                Label("Go to Fastboot", systemImage: "wrench")
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!installState.toolsReady)
                            .opacity(installState.toolsReady ? 1 : 0.3)
                        }
                    }
                    if !installState.toolsReady {
                        VStack(spacing: 4) {
                            Text("Install tools to start fixing your devices!")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                            Button("Go to Settings") {
                                nav.selection = .settings
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(.top, 16)
                    }
                }
                .padding()
                .frame(maxWidth: effectiveWidth > 0 ? effectiveWidth : nil)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }
}

#Preview {
    ContentView().environmentObject(AppNavigation())
}
