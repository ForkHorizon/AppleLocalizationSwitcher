//
//  AppleLocalizationSwitcherApp.swift
//  AppleLocalizationSwitcher
//
//  Created by Kiryl Shcherba on 31/05/2026.
//

import SwiftUI

@main
struct AppleLocalizationSwitcherApp: App {
    @StateObject private var controller = AppController()

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContentView()
                .environmentObject(controller)
        } label: {
            Image(systemName: "globe")
        }
        .menuBarExtraStyle(.menu)
    }
}
