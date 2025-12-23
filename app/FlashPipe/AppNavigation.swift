//
//  AppNavigation.swift
//  FlashPipe
//
//  Created by Ancient Kira on 11/23/25.
//

import SwiftUI
import Combine

final class AppNavigation: ObservableObject {
    @Published var selection: SidebarItem? = .home
}
