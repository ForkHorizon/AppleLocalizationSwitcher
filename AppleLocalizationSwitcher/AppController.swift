//
//  AppController.swift
//  AppleLocalizationSwitcher
//
//  Created by Kiryl Shcherba on 31/05/2026.
//

import ApplicationServices
import AppKit
import Carbon
import Combine
import Foundation
import ServiceManagement

@MainActor
final class AppController: ObservableObject {
    @Published private(set) var inputSources: [KeyboardInputSource] = []
    @Published private(set) var currentInputSource: KeyboardInputSource?
    @Published private(set) var accessibilityTrusted = false
    @Published private(set) var launchAtLoginEnabled = false
    @Published private(set) var tapInstalled = false
    @Published var isSwitcherEnabled: Bool

    private let inputSourceService = InputSourceService()
    private lazy var eventTap = FnEventTap { [weak self] in
        self?.switchToNextInputSource()
    }
    private var permissionTimer: Timer?
    private var notificationTokens: [NSObjectProtocol] = []
    private var lastActionMessage = "Ready"

    var currentSourceName: String {
        currentInputSource?.name ?? "Unknown"
    }

    var canSwitch: Bool {
        inputSources.count >= 2
    }

    var statusText: String {
        if !accessibilityTrusted {
            return "Accessibility permission required"
        }

        if !canSwitch {
            return "Enable at least two input sources"
        }

        if !isSwitcherEnabled {
            return "Fn switcher is off"
        }

        if !tapInstalled {
            return "Fn event tap is not installed"
        }

        return lastActionMessage
    }

    init() {
        isSwitcherEnabled = UserDefaults.standard.object(forKey: DefaultsKey.switcherEnabled) as? Bool ?? true
        refreshAccessibilityTrust()
        refreshInputSources()
        refreshLaunchAtLoginStatus()
        observeInputSourceChanges()
        startPermissionPolling()
        configureEventTap()
    }

    @MainActor
    deinit {
        eventTap.stop()
        permissionTimer?.invalidate()
        notificationTokens.forEach { DistributedNotificationCenter.default().removeObserver($0) }
    }

    func setSwitcherEnabled(_ enabled: Bool) {
        isSwitcherEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: DefaultsKey.switcherEnabled)

        if enabled && !accessibilityTrusted {
            requestAccessibilityPermission()
        }

        configureEventTap()
    }

    func setLaunchAtLoginEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
                lastActionMessage = "Launch at login enabled"
            } else {
                try SMAppService.mainApp.unregister()
                lastActionMessage = "Launch at login disabled"
            }
        } catch {
            lastActionMessage = "Launch at login failed: \(error.localizedDescription)"
        }

        refreshLaunchAtLoginStatus()
    }

    func requestAccessibilityPermission() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        accessibilityTrusted = AXIsProcessTrustedWithOptions(options)

        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }

        configureEventTap()
    }

    func refreshInputSources() {
        inputSources = inputSourceService.enabledSelectableKeyboardInputSources()
        refreshCurrentInputSource()
        configureEventTap()
    }

    func switchToNextInputSource() {
        refreshCurrentInputSource()

        guard inputSources.count >= 2 else {
            lastActionMessage = "Enable at least two input sources"
            configureEventTap()
            return
        }

        let currentID = currentInputSource?.id
        let nextIndex: Int

        if let currentID, let currentIndex = inputSources.firstIndex(where: { $0.id == currentID }) {
            nextIndex = inputSources.index(after: currentIndex) == inputSources.endIndex ? inputSources.startIndex : inputSources.index(after: currentIndex)
        } else {
            nextIndex = inputSources.startIndex
        }

        let nextSource = inputSources[nextIndex]
        let status = inputSourceService.select(nextSource)

        if status == noErr {
            currentInputSource = nextSource
            lastActionMessage = "Switched to \(nextSource.name)"
        } else {
            lastActionMessage = "Switch failed (\(status))"
        }

        configureEventTap()
    }

    private func refreshCurrentInputSource() {
        guard let currentID = inputSourceService.currentKeyboardInputSourceID() else {
            currentInputSource = nil
            return
        }

        currentInputSource = inputSources.first { $0.id == currentID }
    }

    private func refreshAccessibilityTrust() {
        let trusted = AXIsProcessTrusted()

        if trusted != accessibilityTrusted {
            accessibilityTrusted = trusted
            configureEventTap()
        } else {
            accessibilityTrusted = trusted
        }
    }

    private func refreshLaunchAtLoginStatus() {
        launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
    }

    private func configureEventTap() {
        guard isSwitcherEnabled, accessibilityTrusted, canSwitch else {
            eventTap.stop()
            tapInstalled = false
            return
        }

        tapInstalled = eventTap.start()

        if tapInstalled, lastActionMessage == "Ready" {
            lastActionMessage = "Fn switcher ready"
        } else if !tapInstalled {
            lastActionMessage = "Could not install Fn event tap"
        }
    }

    private func observeInputSourceChanges() {
        let center = DistributedNotificationCenter.default()
        let selectedName = Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String)
        let enabledName = Notification.Name(kTISNotifyEnabledKeyboardInputSourcesChanged as String)

        notificationTokens.append(center.addObserver(forName: selectedName, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshCurrentInputSource()
            }
        })

        notificationTokens.append(center.addObserver(forName: enabledName, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshInputSources()
            }
        })
    }

    private func startPermissionPolling() {
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshAccessibilityTrust()
            }
        }
    }
}

private enum DefaultsKey {
    static let switcherEnabled = "switcherEnabled"
}
