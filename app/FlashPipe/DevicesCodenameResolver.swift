//
//  DevicesCodenameResolver.swift
//  FlashPipe
//
//  Created by Ancient Kira on 11/25/25.
//

import Foundation

/// Unified resolver for both Fastboot and ADB codenames using KnownDeviceCodenames.txt.
struct DevicesCodenameResolver {

    private static var map: [String: String] = [:]
    private static var didLoad = false

    // MARK: - Public API

    static func friendly(for code: String) -> String {
        loadIfNeeded()
        let key = code.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return map[key] ?? code   // fallback to codename if unknown
    }

    static func friendly(for code: String, serial: String) async -> String {
        loadIfNeeded()

        // Clean input codename
        let key = code
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedKey = key.replacingOccurrences(of: "_", with: "-")

        // 1️⃣ Try KnownDeviceCodenames.txt
        if let known = map[normalizedKey] {
            return known
        }

        // 2️⃣ Fallback: model (true device name)
        if let model = await adbProp("ro.product.model", serial: serial)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !model.isEmpty, model != "<null>" {
            return model
        }

        // 3️⃣ Fallback: brand + serial  (e.g., "Xiaomi (a1b2c3)")
        if let brand = await adbProp("ro.product.brand", serial: serial)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !brand.isEmpty, brand != "<null>" {
            return "\(brand) (\(serial))"
        }

        // 4️⃣ Final fallback: codename
        return normalizedKey
    }

    private static func adbProp(_ prop: String, serial: String) async -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/adb")
        process.arguments = ["-s", serial, "shell", "getprop", prop]

        let pipe = Pipe()
        process.standardOutput = pipe

        do { try process.run() } catch { return nil }

        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Fastboot Extractors

    /// Extract exact codename from “fastboot getvar product” output
    static func codenameFromFastbootOutput(_ text: String) -> String? {
        let lower = text.lowercased()

        // 1. Standard: "product: begonia"
        if let range = lower.range(of: "product:") {
            let after = lower[range.upperBound...]
            let code = after.split(whereSeparator: { $0.isWhitespace }).first ?? ""
            let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && trimmed != "<null>" { return trimmed }
        }

        // 2. Bootloader old format: "(bootloader) product: begonia"
        if let range = lower.range(of: "(bootloader) product:") {
            let after = lower[range.upperBound...]
            let code = after.split(whereSeparator: { $0.isWhitespace }).first ?? ""
            let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && trimmed != "<null>" { return trimmed }
        }

        return nil
    }

    // MARK: - Mapping Loader

    private static func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        map = loadMap()
    }

    private static func loadMap() -> [String: String] {
        guard let url = Bundle.main.url(forResource: "KnownDeviceCodenames", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return [:] }

        var output: [String: String] = [:]

        for rawLine in text.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("//") || line.hasPrefix("#") { continue }

            let parts = line.components(separatedBy: "=")
            guard parts.count == 2 else { continue }

            let name = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)

            let codes = parts[1]
                .split(separator: "/")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

            for code in codes {
                output[code] = name
            }
        }

        return output
    }
}
