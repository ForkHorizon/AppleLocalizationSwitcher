//
//  InputSourceService.swift
//  AppleLocalizationSwitcher
//
//  Created by Kiryl Shcherba on 31/05/2026.
//

import Carbon
import Foundation

struct KeyboardInputSource: Identifiable, Equatable {
    let id: String
    let name: String
    fileprivate let source: TISInputSource

    static func == (lhs: KeyboardInputSource, rhs: KeyboardInputSource) -> Bool {
        lhs.id == rhs.id
    }
}

final class InputSourceService {
    func enabledSelectableKeyboardInputSources() -> [KeyboardInputSource] {
        let properties: [CFString: Any] = [
            kTISPropertyInputSourceCategory: kTISCategoryKeyboardInputSource as Any,
            kTISPropertyInputSourceIsEnabled: kCFBooleanTrue as Any,
            kTISPropertyInputSourceIsSelectCapable: kCFBooleanTrue as Any
        ]

        let inputSourceList = TISCreateInputSourceList(properties as CFDictionary, false).takeRetainedValue() as NSArray

        return inputSourceList.compactMap { item -> KeyboardInputSource? in
            let source = item as! TISInputSource

            guard booleanProperty(source, kTISPropertyInputSourceIsEnabled),
                  booleanProperty(source, kTISPropertyInputSourceIsSelectCapable),
                  let id = stringProperty(source, kTISPropertyInputSourceID) else {
                return nil
            }

            let name = stringProperty(source, kTISPropertyLocalizedName) ?? id
            return KeyboardInputSource(id: id, name: name, source: source)
        }
    }

    func currentKeyboardInputSourceID() -> String? {
        guard let unmanagedSource = TISCopyCurrentKeyboardInputSource() else {
            return nil
        }

        let source = unmanagedSource.takeRetainedValue()
        return stringProperty(source, kTISPropertyInputSourceID)
    }

    func select(_ inputSource: KeyboardInputSource) -> OSStatus {
        TISSelectInputSource(inputSource.source)
    }

    private func stringProperty(_ inputSource: TISInputSource, _ key: CFString) -> String? {
        guard let pointer = TISGetInputSourceProperty(inputSource, key) else {
            return nil
        }

        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }

    private func booleanProperty(_ inputSource: TISInputSource, _ key: CFString) -> Bool {
        guard let pointer = TISGetInputSourceProperty(inputSource, key) else {
            return false
        }

        return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(pointer).takeUnretainedValue())
    }
}
