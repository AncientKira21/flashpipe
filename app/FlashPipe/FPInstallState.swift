//
//  FPInstallState.swift
//  FlashPipe
//
//  Created by Ancient Kira on 12/6/25.
//


import Foundation
import SwiftUI
import Combine

/// Global installation/tooling readiness state injected as an EnvironmentObject.
/// SidebarView uses this to enable/disable navigation items until required tools are ready.
@MainActor
final class FPInstallState: ObservableObject {
    /// Indicates whether required external tools are installed and ready to use.
    @Published var toolsReady: Bool

    init(toolsReady: Bool = false) {
        self.toolsReady = toolsReady
    }
}

