import SwiftUI
import Charts

struct FileTypesView: View {
    @ObservedObject var scanner: DiskScanner
    @State private var selectedStat: FileTypeStats?

    var stats: [FileTypeStats] { scanner.fileTypeStats() }
    var totalSize: Int64 { stats.reduce(0) { $0 + $1.totalSize } }

    var chartData: [FileTypeStats] {
        let top = Array(stats.prefix(9))
        if stats.count > 9 {
            let rest = stats.dropFirst(9)
            let other = FileTypeStats(
                ext: "_other",
                count: rest.reduce(0) { $0 + $1.count },
                totalSize: rest.reduce(0) { $0 + $1.totalSize }
            )
            return top + [other]
        }
        return top
    }

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 0) {
                Text("By File Type")
                    .font(.title2).fontWeight(.semibold)
                    .padding()

                if #available(macOS 14.0, *) {
                    Chart(chartData) { stat in
                        SectorMark(
                            angle: .value("Size", stat.totalSize),
                            innerRadius: .ratio(0.5),
                            angularInset: 2
                        )
                        .foregroundStyle(by: .value("Type", stat.displayName))
                        .opacity(selectedStat == nil || selectedStat?.ext == stat.ext ? 1.0 : 0.4)
                    }
                    .chartLegend(.hidden)
                    .frame(height: 230)
                    .padding(.horizontal)
                } else {
                    DonutFallbackChart(data: chartData)
                        .frame(height: 230)
                        .padding(.horizontal)
                }

                Divider().padding(.vertical, 6)

                List(stats, selection: $selectedStat) { stat in
                    FileTypeRow(stat: stat, totalSize: totalSize)
                        .tag(stat)
                }
                .listStyle(.plain)
            }
            .frame(minWidth: 340)

            Group {
                if let stat = selectedStat {
                    FileTypeDetailView(
                        stat: stat,
                        files: scanner.allFiles()
                            .filter { $0.fileExtension == stat.ext }
                            .sorted { $0.size > $1.size }
                    )
                } else {
                    Text("Select a file type")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 260)
        }
        .navigationTitle("File Types")
    }
}

struct FileTypeRow: View {
    let stat: FileTypeStats
    let totalSize: Int64

    var percentage: Double {
        totalSize > 0 ? Double(stat.totalSize) / Double(totalSize) * 100 : 0
    }

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 4)
                .fill(typeColor(stat.ext))
                .frame(width: 12, height: 12)
            VStack(alignment: .leading, spacing: 2) {
                Text(stat.displayName).fontWeight(.medium)
                Text("\(stat.count) files")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(stat.formattedSize)
                    .font(.callout.monospacedDigit())
                Text(String(format: "%.1f%%", percentage))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}

struct FileTypeDetailView: View {
    let stat: FileTypeStats
    let files: [FileNode]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(typeColor(stat.ext))
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(stat.displayName)
                        .font(.title2).fontWeight(.semibold)
                    Text("\(stat.count) files · \(stat.formattedSize)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding()

            Divider()
            Text("Largest Files")
                .font(.headline)
                .padding(.horizontal).padding(.top, 10)

            List(Array(files.prefix(100))) { file in
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.name).lineLimit(1)
                    HStack {
                        Text(file.url.deletingLastPathComponent().path)
                            .font(.caption).foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        Text(file.formattedSize)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
            .listStyle(.plain)
        }
    }
}

struct DonutFallbackChart: View {
    let data: [FileTypeStats]
    var total: Int64 { data.reduce(0) { $0 + $1.totalSize } }

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            ZStack {
                ForEach(Array(data.enumerated()), id: \.offset) { idx, stat in
                    let angles = angleRange(upTo: idx)
                    let pct = total > 0 ? Double(stat.totalSize) / Double(total) : 0
                    Circle()
                        .trim(from: angles.start, to: angles.start + pct)
                        .stroke(typeColor(stat.ext), lineWidth: size * 0.22)
                        .rotationEffect(.degrees(-90))
                }
            }
            .frame(width: size, height: size)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func angleRange(upTo index: Int) -> (start: Double, end: Double) {
        var start = 0.0
        for i in 0..<index {
            start += total > 0 ? Double(data[i].totalSize) / Double(total) : 0
        }
        let end = start + (total > 0 ? Double(data[index].totalSize) / Double(total) : 0)
        return (start, end)
    }
}

func typeColor(_ ext: String) -> Color {
    switch ext {
    case "mp4", "mov", "avi", "mkv", "m4v":                return .blue
    case "jpg", "jpeg", "png", "gif", "heic", "webp":      return .green
    case "mp3", "aac", "flac", "wav", "m4a":               return .purple
    case "pdf":                                            return .red
    case "doc", "docx", "txt", "pages", "rtf":             return .orange
    case "zip", "tar", "gz", "rar", "7z":                  return .yellow
    case "app":                                            return .pink
    case "dmg", "pkg":                                     return .mint
    case "swift", "py", "js", "ts", "html", "css":         return .cyan
    default:                                               return .gray
    }
}
