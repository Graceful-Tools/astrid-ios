//  EnglishStrings.swift
//  The English copy for a key, read from the app's `en.lproj` table whatever language the host
//  runs in. A test that compares `NSLocalizedString(key)` to an English literal passes only on an
//  English host; one that wants to pin the English wording reads it from here instead (AITD-537).

import Foundation

enum EnglishStrings {
    private static let table: [String: String] = {
        guard let path = Bundle.main.path(forResource: "Localizable", ofType: "strings",
                                          inDirectory: nil, forLocalization: "en"),
              let table = NSDictionary(contentsOfFile: path) as? [String: String] else { return [:] }
        return table
    }()

    static func text(_ key: String) -> String? { table[key] }
}
