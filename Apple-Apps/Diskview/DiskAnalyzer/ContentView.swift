import SwiftUI

enum AppTab: String, CaseIterable {
    case directories  = "Directories"
    case fileTypes    = "File Types"
    case largestFiles = "Largest Files"

    var icon: String {
        switch self {
        case .directories:  return "folder"
        case .fileTypes:    return "chart.pie"
        case .largestFiles: return "doc.badge.ellipsis"
        }
    }
}

struct ContentView: View {
    @StateObject private var scanner = DiskScanner()
    @State private var selectedTab: AppTab = .directories
    @State private var showFolderPicker = false

    var body: some View {
        NavigationSplitView {
            SidebarView(scanner: scanner,
                        selectedTab: $selectedTab,
                        showFolderPicker: $showFolderPicker)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        } detail: {
            detailContent
        }
        .fileImporter(isPresented: $showFolderPicker,
                      allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                _ = url.startAccessingSecurityScopedResource()
                scanner.scan(url: url)
            }
        }
        .frame(minWidth: 900, minHeight: 600)
    }

    @ViewBuilder
    private var detailContent: some View {
        if scanner.isScanning {
            ScanningView(progress: scanner.progress, onCancel: scanner.cancel)
        } else if let err = scanner.error {
            ErrorView(message: err)
        } else if scanner.rootNode == nil {
            WelcomeView(showFolderPicker: $showFolderPicker)
        } else {
            switch selectedTab {
            case .directories:  DirectoryView(scanner: scanner)
            case .fileTypes:    FileTypesView(scanner: scanner)
            case .largestFiles: LargestFilesView(scanner: scanner)
            }
        }
    }
}
