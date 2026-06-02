//
//  LanguagePersistenceStore.swift
//  AppleLocalizationSwitcher
//
//  Created by OpenAI on 02/06/2026.
//

import AppKit
import Foundation

struct LanguagePersistenceApplication: Identifiable, Equatable {
    var id: String { bundleIdentifier }

    let bundleIdentifier: String
    let displayName: String
    let rememberLayout: Bool
    let isRunning: Bool
    let isFocused: Bool
    let savedInputSourceID: String?
    let savedInputSourceName: String?
}

struct LanguagePersistenceApplicationIdentity: Equatable {
    let bundleIdentifier: String
    let displayName: String
}

@MainActor
final class LanguagePersistenceStore {
    private struct PersistedApplicationPreference: Codable, Equatable {
        var bundleIdentifier: String
        var displayName: String
        var rememberLayout: Bool
        var lastSeenDate: Date
    }

    private struct RunningApplicationSnapshot {
        var bundleIdentifier: String
        var displayName: String
    }

    private enum DefaultsKey {
        static let enabled = "languagePersistenceEnabled"
        static let appPreferences = "languagePersistenceAppPreferences"
    }

    private let defaults: UserDefaults
    private var preferences: [String: PersistedApplicationPreference]
    private var runningApplications: [String: RunningApplicationSnapshot] = [:]
    private var appLayouts: [String: String] = [:]
    private var availableInputSourceIDs: [String] = []
    private var inputSourceNames: [String: String] = [:]

    private(set) var isEnabled: Bool
    private(set) var focusedApplication: LanguagePersistenceApplicationIdentity?
    private(set) var globalDefaultInputSourceID: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        preferences = Self.loadPreferences(from: defaults)
        isEnabled = defaults.object(forKey: DefaultsKey.enabled) as? Bool ?? false
    }

    var focusedApplicationName: String {
        focusedApplication?.displayName ?? "Global Default"
    }

    var globalDefaultInputSourceName: String {
        guard let globalDefaultInputSourceID else {
            return "Not Set"
        }

        return inputSourceNames[globalDefaultInputSourceID] ?? "Unavailable"
    }

    var applications: [LanguagePersistenceApplication] {
        let focusedBundleIdentifier = focusedApplication?.bundleIdentifier
        let bundleIdentifiers = Set(preferences.keys).union(runningApplications.keys)

        return bundleIdentifiers.compactMap { bundleIdentifier in
            guard let preference = preferences[bundleIdentifier] else {
                return nil
            }

            let savedInputSourceID = appLayouts[bundleIdentifier]
            return LanguagePersistenceApplication(
                bundleIdentifier: bundleIdentifier,
                displayName: runningApplications[bundleIdentifier]?.displayName ?? preference.displayName,
                rememberLayout: preference.rememberLayout,
                isRunning: runningApplications[bundleIdentifier] != nil,
                isFocused: focusedBundleIdentifier == bundleIdentifier,
                savedInputSourceID: savedInputSourceID,
                savedInputSourceName: savedInputSourceID.flatMap { inputSourceNames[$0] }
            )
        }
        .sorted { lhs, rhs in
            if lhs.isFocused != rhs.isFocused {
                return lhs.isFocused
            }

            if lhs.isRunning != rhs.isRunning {
                return lhs.isRunning
            }

            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        defaults.set(enabled, forKey: DefaultsKey.enabled)
    }

    func setRememberLayout(for bundleIdentifier: String, enabled: Bool) {
        guard var preference = preferences[bundleIdentifier] else {
            return
        }

        preference.rememberLayout = enabled
        preference.lastSeenDate = Date()
        preferences[bundleIdentifier] = preference

        if !enabled {
            appLayouts[bundleIdentifier] = nil
        }

        savePreferences()
    }

    func updateInputSources(_ inputSources: [KeyboardInputSource]) {
        availableInputSourceIDs = inputSources.map(\.id)
        inputSourceNames = Dictionary(uniqueKeysWithValues: inputSources.map { ($0.id, $0.name) })

        pruneUnavailableLayouts()
    }

    func initializeGlobalDefaultIfNeeded(currentInputSourceID: String?) {
        guard globalDefaultInputSourceID == nil,
              let currentInputSourceID,
              isAvailableInputSourceID(currentInputSourceID) else {
            return
        }

        globalDefaultInputSourceID = currentInputSourceID
    }

    func refreshRunningApplications(_ applications: [NSRunningApplication], ownBundleIdentifier: String?) {
        var nextRunningApplications: [String: RunningApplicationSnapshot] = [:]

        for application in applications {
            guard let snapshot = snapshot(for: application, ownBundleIdentifier: ownBundleIdentifier) else {
                continue
            }

            upsertPreference(for: snapshot)
            nextRunningApplications[snapshot.bundleIdentifier] = snapshot
        }

        runningApplications = nextRunningApplications
        savePreferences()
    }

    func focus(application: NSRunningApplication?, ownBundleIdentifier: String?) {
        guard let application,
              let snapshot = snapshot(for: application, ownBundleIdentifier: ownBundleIdentifier) else {
            focusedApplication = nil
            return
        }

        upsertPreference(for: snapshot)
        runningApplications[snapshot.bundleIdentifier] = snapshot
        focusedApplication = LanguagePersistenceApplicationIdentity(
            bundleIdentifier: snapshot.bundleIdentifier,
            displayName: snapshot.displayName
        )
        savePreferences()
    }

    func recordSelectedInputSourceID(_ inputSourceID: String) {
        guard isEnabled, isAvailableInputSourceID(inputSourceID) else {
            return
        }

        if let focusedApplication,
           preferences[focusedApplication.bundleIdentifier]?.rememberLayout == true {
            appLayouts[focusedApplication.bundleIdentifier] = inputSourceID
        } else {
            globalDefaultInputSourceID = inputSourceID
        }
    }

    func targetInputSourceID(currentInputSourceID: String?) -> String? {
        guard isEnabled else {
            return nil
        }

        pruneUnavailableLayouts()

        if let focusedApplication,
           preferences[focusedApplication.bundleIdentifier]?.rememberLayout == true,
           let appInputSourceID = appLayouts[focusedApplication.bundleIdentifier],
           isAvailableInputSourceID(appInputSourceID) {
            return appInputSourceID
        }

        if let globalDefaultInputSourceID, isAvailableInputSourceID(globalDefaultInputSourceID) {
            return globalDefaultInputSourceID
        }

        if let currentInputSourceID, isAvailableInputSourceID(currentInputSourceID) {
            return currentInputSourceID
        }

        return availableInputSourceIDs.first
    }

    private func upsertPreference(for snapshot: RunningApplicationSnapshot) {
        let existingPreference = preferences[snapshot.bundleIdentifier]
        preferences[snapshot.bundleIdentifier] = PersistedApplicationPreference(
            bundleIdentifier: snapshot.bundleIdentifier,
            displayName: snapshot.displayName,
            rememberLayout: existingPreference?.rememberLayout ?? true,
            lastSeenDate: Date()
        )
    }

    private func snapshot(
        for application: NSRunningApplication,
        ownBundleIdentifier: String?
    ) -> RunningApplicationSnapshot? {
        guard application.activationPolicy == .regular,
              !application.isTerminated,
              let bundleIdentifier = application.bundleIdentifier,
              bundleIdentifier != ownBundleIdentifier else {
            return nil
        }

        return RunningApplicationSnapshot(
            bundleIdentifier: bundleIdentifier,
            displayName: application.localizedName ?? bundleIdentifier
        )
    }

    private func pruneUnavailableLayouts() {
        guard !availableInputSourceIDs.isEmpty else {
            return
        }

        let availableInputSourceIDs = Set(availableInputSourceIDs)
        appLayouts = appLayouts.filter { availableInputSourceIDs.contains($0.value) }

        if let globalDefaultInputSourceID, !availableInputSourceIDs.contains(globalDefaultInputSourceID) {
            self.globalDefaultInputSourceID = nil
        }
    }

    private func isAvailableInputSourceID(_ inputSourceID: String) -> Bool {
        availableInputSourceIDs.contains(inputSourceID)
    }

    private func savePreferences() {
        guard let data = try? JSONEncoder().encode(Array(preferences.values)) else {
            return
        }

        defaults.set(data, forKey: DefaultsKey.appPreferences)
    }

    private static func loadPreferences(from defaults: UserDefaults) -> [String: PersistedApplicationPreference] {
        guard let data = defaults.data(forKey: DefaultsKey.appPreferences),
              let decodedPreferences = try? JSONDecoder().decode([PersistedApplicationPreference].self, from: data) else {
            return [:]
        }

        return Dictionary(uniqueKeysWithValues: decodedPreferences.map { ($0.bundleIdentifier, $0) })
    }
}
