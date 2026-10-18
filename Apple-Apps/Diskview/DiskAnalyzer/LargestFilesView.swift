import SwiftUI

struct LargestFilesView: View {
    @ObservedObject var scanner: DiskScanner
    @State private var searchText = ""
    @State private var limit = 100
    @State private var sortOrder = [KeyPathComparator(\FileNode.size, order: .reverse)]

    var displayedFiles: [FileNode] {
        let base = scanner.largestFiles(limit: limit)
        guard !searchText.isEmpty else { return base }
        return base.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.url.path.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            toolbar
            Divider()
            fileTable
        }
        .navigationTitle("Largest Files")
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Text("Largest Files")
                .font(.title2).fontWeight(.semibold)
            Spacer()
            Picker("Show top", selection: $limit) {
                Text("Top 50").tag(50)
                Text("Top 100").tag(100)
                Text("Top 250").tag(250)
                Text("Top 500").tag(500)
            }
            .pickerStyle(.segmented)
            .frame(width: 290)
            TextField("Search", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 160)
        }
        .padding()
    }

    private var fileTable: some View {
        Table(displayedFiles, sortOrder: $sortOrder) {
            TableColumn("Name") { file in
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.name)
                        .lineLimit(1)
                    Text(file.url.deletingLastPathComponent().path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            TableColumn("Type", value: \.fileExtension) { file in
                Text(file.fileExtension.isEmpty ? "–" : file.fileExtension.uppercased())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .width(55)
            TableColumn("Size", value: \.size) { file in
                HStack {
                    Spacer()
                    Text(file.formattedSize)
                        .font(.callout.monospacedDigit())
                }
            }
            .width(90)
        }
        .onChange(of: sortOrder) { newOrder in
            // Table handles sorting via sortOrder binding automatically
            _ = newOrder
        }
    }
}
