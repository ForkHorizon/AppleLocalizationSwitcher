//
//  SettingsView.swift
//  AppleLocalizationSwitcher
//
//  Created by OpenAI on 02/06/2026.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var controller: AppController

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: Binding(
                    get: { controller.isLanguagePersistenceEnabled },
                    set: { controller.setLanguagePersistenceEnabled($0) }
                )) {
                    Label("Enable Language Layout Persistence", systemImage: "textformat")
                }

                LabeledContent("Active Context", value: controller.focusedApplicationName)
                LabeledContent("Global Default", value: controller.globalDefaultSourceName)
            }

            Divider()

            HStack {
                Text("Applications")
                    .font(.headline)

                Spacer()

                Button {
                    controller.refreshLanguagePersistenceApplications()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }

            if controller.languagePersistenceApplications.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "app.dashed")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("No regular applications have been seen yet.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(controller.languagePersistenceApplications) { application in
                            LanguagePersistenceApplicationRow(
                                application: application,
                                globalDefaultSourceName: controller.globalDefaultSourceName,
                                setRememberLayout: { enabled in
                                    controller.setRememberLanguageLayout(
                                        for: application.bundleIdentifier,
                                        enabled: enabled
                                    )
                                }
                            )

                            if application.id != controller.languagePersistenceApplications.last?.id {
                                Divider()
                            }
                        }
                    }
                }
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                )
            }
        }
        .padding(20)
        .frame(minWidth: 620, minHeight: 440)
    }
}

private struct LanguagePersistenceApplicationRow: View {
    let application: LanguagePersistenceApplication
    let globalDefaultSourceName: String
    let setRememberLayout: (Bool) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: application.isRunning ? "app.fill" : "app")
                .foregroundStyle(application.isRunning ? .primary : .secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(application.displayName)
                        .fontWeight(application.isFocused ? .semibold : .regular)
                        .lineLimit(1)

                    if application.isFocused {
                        Text("Focused")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.14))
                            .clipShape(Capsule())
                    }

                    if !application.isRunning {
                        Text("Not Running")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(application.bundleIdentifier)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(layoutText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 16)

            Toggle(isOn: Binding(
                get: { application.rememberLayout },
                set: setRememberLayout
            )) {
                Text("Remember Layout")
            }
            .toggleStyle(.switch)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var layoutText: String {
        if application.rememberLayout {
            return "Saved layout: \(application.savedInputSourceName ?? "None")"
        }

        return "Uses global default: \(globalDefaultSourceName)"
    }
}
