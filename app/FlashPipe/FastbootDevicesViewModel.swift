//
//  FastbootDevicesViewModel.swift
//  FlashPipe
//
//  Created by Ancient Kira on 11/23/25.
//

import SwiftUI
import Combine
import Foundation

struct FastbootDevice: Identifiable {
    let id = UUID()
    let serial: String
    let product: String
    let displayName: String
}

final class FastbootDevicesViewModel: ObservableObject {
    @Published var devices: [FastbootDevice] = []
    @Published var selectedSerial: String? = nil
    @Published var isScanning: Bool = false

    private var scanTask: Task<Void, Never>? = nil

    func startScanning() {
        stopScanning()
        isScanning = true
        scanTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.refreshDevicesOnce()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    func stopScanning() {
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
    }

    @MainActor
    private func refreshDevicesOnce() async {
        let listResult = await Self.runFastbootDevices()
        guard case .success(let rawList) = listResult else {
            devices = []
            selectedSerial = nil
            return
        }

        let serials = Self.parseFastbootList(rawList)
        var newDevices: [FastbootDevice] = []

        for serial in serials {
            let productRaw = (try? await Self.runShell(["/bin/zsh", "-lc", "fastboot -s \(serial) getvar product"]).get()) ?? ""
            let product = DevicesCodenameResolver.codenameFromFastbootOutput(productRaw) ?? "unknown"
            let friendly = DevicesCodenameResolver.friendly(for: product)
            let display = "\(friendly) (\(serial))"
            newDevices.append(FastbootDevice(serial: serial, product: product, displayName: display))
        }

        devices = newDevices

        if newDevices.count >= 1 {
            if selectedSerial == nil, let first = newDevices.first?.serial {
                selectedSerial = first
            }
            stopScanning()
        }
    }

    private static func runFastbootDevices() async -> Result<String, Error> {
        await runShell(["/bin/zsh", "-lc", "fastboot devices"])    
    }

    private static func parseFastbootList(_ text: String) -> [String] {
        text.split(separator: "\n").compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let parts = trimmed.split(separator: "\t")
            return parts.first.map { String($0) }
        }
    }

    static func runShell(_ args: [String]) async -> Result<String, Error> {
        return await withCheckedContinuation { cont in
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: args[0])
            process.arguments = Array(args.dropFirst())
            process.standardOutput = pipe
            process.standardError = pipe

            let timeoutTask = Task {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                if !process.isRunning {
                    return
                }
                process.terminate()
            }

            do { try process.run() }
            catch {
                timeoutTask.cancel()
                cont.resume(returning: .failure(error))
                return
            }

            process.terminationHandler = { proc in
                timeoutTask.cancel()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(decoding: data, as: UTF8.self)

                if proc.terminationStatus == 0 {
                    cont.resume(returning: .success(output))
                } else {
                    cont.resume(returning: .failure(
                        NSError(
                            domain: "fastboot",
                            code: Int(proc.terminationStatus),
                            userInfo: [NSLocalizedDescriptionKey: output]
                        )
                    ))
                }
            }
        }
    }
}
