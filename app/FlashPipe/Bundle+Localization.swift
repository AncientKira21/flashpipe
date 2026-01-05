//
//  Bundle+Localization.swift
//  FlashPipe
//
//  Created by Ancient Kira on 12/14/25.
//

import Foundation

private var bundleKey: UInt8 = 0

final class LanguageBundle: Bundle, @unchecked Sendable {
    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        if let override = objc_getAssociatedObject(self, &bundleKey) as? Bundle {
            return override.localizedString(forKey: key, value: value, table: tableName)
        }
        return super.localizedString(forKey: key, value: value, table: tableName)
    }
}

extension Bundle {
    static func setLanguage(_ lang: String) {
        object_setClass(Bundle.main, LanguageBundle.self)

        let path = Bundle.main.path(forResource: lang, ofType: "lproj") ?? Bundle.main.path(forResource: "en", ofType: "lproj")

        let overrideBundle =
            path != nil ? Bundle(path: path!) : nil

        objc_setAssociatedObject(Bundle.main, &bundleKey, overrideBundle, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
}
