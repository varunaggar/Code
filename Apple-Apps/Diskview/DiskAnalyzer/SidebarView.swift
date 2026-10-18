import SwiftUI

struct SidebarView: View {
    @ObservedObject var scanner: DiskScanner
    @Binding var selectedTab: AppTab
    @Binding var showFolderPicker: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            tabList
            Spacer()
            Divider()
            footer
        }
        .frame(maxHeight: .infinity)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Disk Analyzer")
                .font(.headline)
            if let url = scanner.scannedURL {
                Text(url.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding()
    }

    private var tabList: some View {
        VStack(spacing: 2) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    Label(tab.rawValue, systemImage: tab.icon)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(
                            selectedTab == tab
                                ? Color.accentColor.opacity(0.15)
                                : Color.clear
                        )
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .disabled(scanner.rootNode == nil)
            }
        }
        .padding(.top, 8)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                showFolderPicker = true
            } label: {
                Label(scanner.rootNode == nil ? "Choose Folder" : "Scan New Folder",
                      systemImage: "folder.badge.magnifyingglass")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            if let root = scanner.rootNode {
                HStack {
                    Text(root.formattedSize)
                    Spacer()
                    Text("\(scanner.allFiles().count) files")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}
