//
//  LanguageSwitchFeedbackView.swift
//  AppleLocalizationSwitcher
//

import Combine
import SwiftUI

@MainActor
final class LanguageSwitchFeedbackContentModel: ObservableObject {
    @Published var snapshot: LanguageSwitchFeedbackSnapshot

    init(snapshot: LanguageSwitchFeedbackSnapshot) {
        self.snapshot = snapshot
    }
}

struct LanguageSwitchFeedbackView: View {
    @ObservedObject var model: LanguageSwitchFeedbackContentModel
    @Namespace private var glassNamespace

    var body: some View {
        let snapshot = model.snapshot

        GlassEffectContainer(spacing: 10) {
            VStack(spacing: 14) {
                Text(snapshot.selectedSourceName)
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
                    .frame(maxWidth: .infinity)

                HStack(spacing: 8) {
                    ForEach(snapshot.sources) { source in
                        sourceChip(source, selectedSourceID: snapshot.selectedSourceID)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .glassEffect(.regular.interactive(false), in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            .glassEffectTransition(.materialize)
        }
        .padding(10)
        .frame(width: 430, height: 132)
        .animation(.smooth(duration: 0.16), value: snapshot)
    }

    private func sourceChip(_ source: LanguageSwitchFeedbackItem, selectedSourceID: String) -> some View {
        let isSelected = source.id == selectedSourceID

        return Text(abbreviation(for: source.name))
            .font(.system(size: 14, weight: isSelected ? .semibold : .medium, design: .rounded))
            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: 42, height: 34)
            .glassEffect(chipGlass(selected: isSelected), in: Capsule())
            .glassEffectID(source.id, in: glassNamespace)
            .accessibilityLabel(source.name)
    }

    private func chipGlass(selected: Bool) -> Glass {
        if selected {
            return Glass.regular.tint(Color.accentColor.opacity(0.24)).interactive(false)
        }

        return Glass.clear.interactive(false)
    }

    private func abbreviation(for name: String) -> String {
        let words = name
            .split { character in
                character == " " || character == "-" || character == "_" || character == "."
            }
            .filter { !$0.isEmpty }

        let initials = words.prefix(2).compactMap(\.first)
        if !initials.isEmpty {
            return String(initials).uppercased()
        }

        return String(name.prefix(2)).uppercased()
    }
}
