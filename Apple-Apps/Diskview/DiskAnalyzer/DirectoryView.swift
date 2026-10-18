import SwiftUI

struct DirectoryView: View {
    @ObservedObject var scanner: DiskScanner
    @State private var selectedNode: FileNode?

    var body: some View {
        HSplitView {
            treePanel
                .frame(minWidth: 300)
            detailPanel
                .frame(minWidth: 260)
        }
    }

    private var treePanel: some View {
        List(scanner.rootNode.map { [$0] } ?? [],
             children: \.childrenForOutline,
             selection: $selectedNode) { node in
            NodeRow(node: node, totalSize: scanner.rootNode?.size ?? 1)
                .tag(node)
        }
        .listStyle(.sidebar)
        .navigationTitle("Directory Breakdown")
    }

    @ViewBuilder
    private var detailPanel: some View {
        if let node = selectedNode {
            DirectoryDetailView(node: node, totalSize: scanner.rootNode?.size ?? 1)
        } else {
            Text("Select a folder")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct NodeRow: View {
    let node: FileNode
    let totalSize: Int64

    var percentage: Double {
        totalSize > 0 ? Double(node.size) / Double(totalSize) * 100 : 0
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: node.isDirectory ? "folder.fill" : "doc.fill")
                .foregroundStyle(node.isDirectory ? .yellow : Color.secondary)
                .frame(width: 18)

            Text(node.name)
                .lineLimit(1)

            Spacer()

            Text(String(format: "%.1f%%", percentage))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)

            Text(node.formattedSize)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .trailing)
        }
    }
}

struct DirectoryDetailView: View {
    let node: FileNode
    let totalSize: Int64

    var percentage: Double {
        totalSize > 0 ? Double(node.size) / Double(totalSize) * 100 : 0
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                iconHeader
                Divider()
                statsGrid
                if node.isDirectory && !node.children.isEmpty {
                    childrenChart
                }
                Spacer()
            }
            .padding()
        }
    }

    private var iconHeader: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: node.isDirectory ? "folder.fill" : "doc.fill")
                .font(.system(size: 36))
                .foregroundStyle(node.isDirectory ? .yellow : .blue)
            VStack(alignment: .leading, spacing: 3) {
                Text(node.name)
                    .font(.title2).fontWeight(.semibold)
                    .lineLimit(2)
                Text(node.url.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private var statsGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 8) {
            GridRow {
                Text("Total Size").foregroundStyle(.secondary)
                Text(node.formattedSize).fontWeight(.medium)
            }
            GridRow {
                Text("% of scan").foregroundStyle(.secondary)
                Text(String(format: "%.2f%%", percentage)).fontWeight(.medium)
            }
            if node.isDirectory {
                GridRow {
                    Text("Direct items").foregroundStyle(.secondary)
                    Text("\(node.children.count)").fontWeight(.medium)
                }
            }
        }
    }

    private var childrenChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Top Contents")
                .font(.headline)
                .padding(.top, 4)

            ForEach(node.children.prefix(10)) { child in
                let pct = node.size > 0 ? CGFloat(child.size) / CGFloat(node.size) : 0
                HStack(spacing: 8) {
                    Image(systemName: child.isDirectory ? "folder.fill" : "doc")
                        .foregroundStyle(child.isDirectory ? .yellow : .secondary)
                        .frame(width: 16)
                    Text(child.name)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.secondary.opacity(0.15))
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.accentColor.opacity(0.6))
                                .frame(width: geo.size.width * pct)
                        }
                    }
                    .frame(height: 10)
                    Text(child.formattedSize)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 68, alignment: .trailing)
                }
            }
        }
    }
}
