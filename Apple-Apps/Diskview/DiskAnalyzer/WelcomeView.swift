import SwiftUI

struct WelcomeView: View {
    @Binding var showFolderPicker: Bool

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "internaldrive")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text("Analyze Your Disk")
                .font(.largeTitle)
                .fontWeight(.semibold)
            Text("Choose a folder to see a breakdown of disk usage\nby directory, file type, and size.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Choose Folder…") {
                showFolderPicker = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ScanningView: View {
    let progress: String
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text(progress.isEmpty ? "Scanning…" : progress)
                .foregroundStyle(.secondary)
            Button("Cancel", action: onCancel)
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ErrorView: View {
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.red)
            Text("Scan Failed")
                .font(.title2)
                .fontWeight(.semibold)
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
