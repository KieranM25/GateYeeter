//
//  ContentView.swift
//  Gatekeeper Flag Remover
//
//  Created by Kieran Moore on 09/04/2025.
//

import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct FileDropView: View {
    @State private var statusMessage: String = "Drop your files here"
    @State private var statusIcon: String = "arrow.down.doc"
    @State private var statusColor: Color = .accentColor
    @State private var isTargeted: Bool = false
    @State private var results: [String] = []

    var body: some View {
        VStack(spacing: 20) {
            Text("GateYeeter")
                .font(.largeTitle.bold())
                .padding(.top)

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
                    .stroke(Color.accentColor.opacity(isTargeted ? 0.8 : 0.4), style: StrokeStyle(lineWidth: 2, dash: [10]))
            )
            .background(isTargeted ? Color.accentColor.opacity(0.05) : .clear)
            .cornerRadius(16)
            .shadow(radius: 8)
            .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isTargeted) { providers in
                handleDrop(providers: providers)
            }

            if !results.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(results, id: \.self) { result in
                            Label(result, systemImage: "checkmark.seal.fill")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal)
                }
                .frame(height: 100)
            }

            Text("This app removes the Gatekeeper quarantine flag from dropped files.")
                .font(.footnote)
                .foregroundColor(.secondary)
                .padding(.bottom)
        }
        .padding()
        .frame(minWidth: 420, minHeight: 380)
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { (item, error) in
                if let data = item as? Data,
                   let fileURL = URL(dataRepresentation: data, relativeTo: nil) {
                    removeQuarantineFlag(fileURL: fileURL)
                }
            }
        }
        return true
    }

    private func removeQuarantineFlag(fileURL: URL) {
        let process = Process()
        process.launchPath = "/usr/bin/xattr"
        process.arguments = ["-d", "com.apple.quarantine", fileURL.path]

        let pipe = Pipe()
        process.standardError = pipe
        process.standardOutput = pipe

        let fileHandle = pipe.fileHandleForReading

        do {
            try process.run()
            process.waitUntilExit()

            let data = fileHandle.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? "No output"

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if process.terminationStatus == 0 {
                    NSSound(named: NSSound.Name("Hero"))?.play()

                    statusIcon = "checkmark.circle.fill"
                    statusColor = .green.opacity(0.8)
                    statusMessage = "✅ Quarantine Flags Yeeted! from:\n\(fileURL.lastPathComponent)"
                    results.insert("Yeeted: \(fileURL.lastPathComponent)", at: 0)
                } else {
                    statusIcon = "xmark.octagon.fill"
                    statusColor = .red.opacity(0.7)
                    statusMessage = "❌ No Flags to remove on:\n\(fileURL.lastPathComponent)"
                    results.insert("No flag: \(fileURL.lastPathComponent)", at: 0)
                }
            }
        } catch {
            DispatchQueue.main.async {
                statusIcon = "exclamationmark.triangle.fill"
                statusColor = .yellow.opacity(0.8)
                statusMessage = "⚠️ Error: \(error.localizedDescription)"
                results.insert("⚠️ Error on: \(fileURL.lastPathComponent)", at: 0)
            }
        }
    }
}
