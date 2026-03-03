//
//  ContentView.swift
//  GateYeeter
//
//  Created by Kieran Moore on 09/04/2025.
//

import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct YeetResult: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let outcome: Outcome
    let blockedBefore: Bool
    let blockedAfter: Bool
    let message: String

    enum Outcome {
        case yeeted
        case noFlag
        case failed
    }
}

struct FileDropView: View {

    @State private var statusMessage: String = "Drop your files here"
    @State private var statusIcon: String = "arrow.down.doc"
    @State private var statusColor: Color = .accentColor
    @State private var isTargeted: Bool = false
    @State private var results: [YeetResult] = []
    @State private var gatekeeperStatus: String = "Checking Gatekeeper..."
    @State private var openAfterCleaning: Bool = false
    @State private var openInSuspiciousPackage: Bool = false

    var body: some View {
        VStack(spacing: 20) {

            Text("GateYeeter")
                .font(.largeTitle.bold())
                .padding(.top)

            Label(
                gatekeeperStatus,
                systemImage: gatekeeperStatus.contains("Enabled") ? "lock.shield" : "lock.open"
            )
            .foregroundColor(
                gatekeeperStatus.contains("Enabled") ? .green : .orange
            )

            // Drop Zone
            VStack(spacing: 10) {
                Image(systemName: statusIcon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 60, height: 60)
                    .foregroundColor(statusColor)
                    .shadow(radius: 4)

                Text(statusMessage)
                    .font(.system(.title3, design: .rounded))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding()
            .frame(maxWidth: .infinity, minHeight: 200)
            .background(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        Color.accentColor.opacity(isTargeted ? 0.8 : 0.4),
                        style: StrokeStyle(lineWidth: 2, dash: [10])
                    )
            )
            .background(isTargeted ? Color.accentColor.opacity(0.05) : .clear)
            .cornerRadius(16)
            .shadow(radius: 8)
            .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isTargeted) { providers in
                handleDrop(providers: providers)
            }

            // Results
            if !results.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(results) { result in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: icon(for: result))
                                    .foregroundColor(color(for: result))
                                    .padding(.top, 2)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(result.url.lastPathComponent)
                                        .font(.caption.bold())

                                    Text(resultLine(for: result))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)

                                    if result.outcome == .failed {
                                        Text(result.message)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                            .lineLimit(2)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .frame(height: 140)
            }

            // Toggles
            Toggle("Open file after cleaning", isOn: $openAfterCleaning)
                .toggleStyle(.switch)
                .padding(.horizontal)
                .onChange(of: openAfterCleaning) { _, newValue in
                    if newValue { openInSuspiciousPackage = false }
                }

            Toggle("Open in Suspicious Package (PKG only)", isOn: $openInSuspiciousPackage)
                .toggleStyle(.switch)
                .padding(.horizontal)
                .onChange(of: openInSuspiciousPackage) { _, newValue in
                    if newValue { openAfterCleaning = false }
                }

            Text("This app Yeets the Gatekeeper quarantine flag from dropped files.")
                .font(.footnote)
                .foregroundColor(.secondary)
                .padding(.bottom)
        }
        .padding()
        .frame(minWidth: 420, minHeight: 440)
        .onAppear {
            gatekeeperStatus = isGatekeeperEnabled()
                ? "Gatekeeper: Enabled"
                : "Gatekeeper: Disabled"
        }
    }
}

// MARK: - Drop Handling

extension FileDropView {

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let data = item as? Data,
                   let fileURL = URL(dataRepresentation: data, relativeTo: nil) {
                    processFile(fileURL)
                }
            }
        }
        return true
    }

    private func processFile(_ fileURL: URL) {
        DispatchQueue.global(qos: .userInitiated).async {

            let hadFlag = hasQuarantine(fileURL)
            let blockedBefore = assessGatekeeper(fileURL)

            var outcome: YeetResult.Outcome = .noFlag
            var message = "No quarantine attribute present"

            if hadFlag {
                let removal = removeQuarantine(fileURL)
                if removal.success {
                    outcome = .yeeted
                    message = "Quarantine removed"
                } else {
                    outcome = .failed
                    message = removal.message
                }
            }

            let blockedAfter = assessGatekeeper(fileURL)

            DispatchQueue.main.async {

                let result = YeetResult(
                    url: fileURL,
                    outcome: outcome,
                    blockedBefore: blockedBefore,
                    blockedAfter: blockedAfter,
                    message: message
                )

                results.insert(result, at: 0)

                updateStatusUI(for: result)

                // Open behaviour:
                // - If Suspicious Package toggle is on: attempt to open PKG/MPKG in Suspicious Package (regardless of outcome)
                // - Else, if Open After Cleaning is on: open only when we actually removed quarantine
                if openInSuspiciousPackage {
                    openWithSuspiciousPackage(fileURL)
                } else if outcome == .yeeted && openAfterCleaning {
                    NSWorkspace.shared.open(fileURL)
                }
            }
        }
    }
}

// MARK: - UI Helpers

extension FileDropView {

    private func updateStatusUI(for result: YeetResult) {
        switch result.outcome {
        case .yeeted:
            NSSound(named: NSSound.Name("Hero"))?.play()
            statusIcon = "checkmark.circle.fill"
            statusColor = .green.opacity(0.8)
            statusMessage = "✅ Quarantine flag yeeted from:\n\(result.url.lastPathComponent)"

        case .noFlag:
            statusIcon = "minus.circle.fill"
            statusColor = .secondary
            statusMessage = "ℹ️ No quarantine flag on:\n\(result.url.lastPathComponent)"

        case .failed:
            statusIcon = "exclamationmark.triangle.fill"
            statusColor = .yellow.opacity(0.8)
            statusMessage = "⚠️ Failed to remove flag from:\n\(result.url.lastPathComponent)"
        }
    }

    private func icon(for result: YeetResult) -> String {
        switch result.outcome {
        case .yeeted: return "checkmark.seal.fill"
        case .noFlag: return "minus.circle"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    private func color(for result: YeetResult) -> Color {
        switch result.outcome {
        case .yeeted: return .green
        case .noFlag: return .secondary
        case .failed: return .yellow
        }
    }

    private func resultLine(for result: YeetResult) -> String {
        let before = result.blockedBefore ? "Yes" : "No"
        let after = result.blockedAfter ? "Yes" : "No"
        return "Blocked: \(before) → \(after)"
    }
}

// MARK: - System Calls

extension FileDropView {

    private func run(_ exec: String, _ args: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: exec)
        process.arguments = args

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            return (process.terminationStatus,
                    output.trimmingCharacters(in: .whitespacesAndNewlines))

        } catch {
            return (-1, error.localizedDescription)
        }
    }

    private func hasQuarantine(_ url: URL) -> Bool {
        let result = run("/usr/bin/xattr", ["-p", "com.apple.quarantine", url.path])
        return result.status == 0 && !result.output.isEmpty
    }

    private func removeQuarantine(_ url: URL) -> (success: Bool, message: String) {
        let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false

        let args = isDir
            ? ["-dr", "com.apple.quarantine", url.path]
            : ["-d",  "com.apple.quarantine", url.path]

        let result = run("/usr/bin/xattr", args)

        if result.status == 0 {
            return (true, "Removed quarantine")
        } else {
            return (false, result.output.isEmpty ? "Removal failed" : result.output)
        }
    }

    private func assessGatekeeper(_ url: URL) -> Bool {
        let result = run("/usr/sbin/spctl", ["--assess", "--type", "execute", url.path])
        return result.status != 0
    }

    private func isGatekeeperEnabled() -> Bool {
        let result = run("/usr/sbin/spctl", ["--status"])
        return result.output.contains("enabled")
    }

    private func openWithSuspiciousPackage(_ url: URL) {
        let appURL = URL(fileURLWithPath: "/Applications/Suspicious Package.app")

        // Only meaningful for installer packages
        let ext = url.pathExtension.lowercased()
        guard ext == "pkg" || ext == "mpkg" else { return }

        let config = NSWorkspace.OpenConfiguration()
        config.activates = true

        NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: config) { _, error in
            if let error = error {
                DispatchQueue.main.async {
                    statusIcon = "exclamationmark.triangle.fill"
                    statusColor = .yellow.opacity(0.8)
                    statusMessage = "⚠️ Couldn't open in Suspicious Package:\n\(error.localizedDescription)"
                }
            }
        }
    }
}
