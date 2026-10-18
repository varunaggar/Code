import Foundation

final class FileNode: Identifiable, Hashable {
    static func == (lhs: FileNode, rhs: FileNode) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    let id = UUID()
    let url: URL
    let name: String
    let isDirectory: Bool
    var size: Int64 = 0
    var children: [FileNode] = []

    var fileExtension: String {
        isDirectory ? "" : url.pathExtension.lowercased()
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    var childrenForOutline: [FileNode]? {
        isDirectory && !children.isEmpty ? children : nil
    }

    init(url: URL, isDirectory: Bool) {
        self.url = url
        self.name = url.lastPathComponent
        self.isDirectory = isDirectory
    }
}

struct FileTypeStats: Identifiable, Hashable {
    let id = UUID()
    let ext: String
    let count: Int
    let totalSize: Int64

    var displayName: String { Self.categoryName(for: ext) }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }

    static func categoryName(for ext: String) -> String {
        switch ext {
        case "mp4", "mov", "avi", "mkv", "m4v", "wmv":       return "Video"
        case "jpg", "jpeg", "png", "gif", "heic", "webp",
             "tiff", "bmp", "raw":                            return "Images"
        case "mp3", "aac", "flac", "wav", "m4a", "ogg":      return "Audio"
        case "pdf":                                           return "PDF"
        case "doc", "docx", "txt", "pages", "rtf", "odt",
             "xls", "xlsx", "ppt", "pptx", "numbers", "key": return "Documents"
        case "zip", "tar", "gz", "rar", "7z", "bz2", "xz":  return "Archives"
        case "app":                                           return "Applications"
        case "dmg", "pkg", "iso":                            return "Disk Images"
        case "swift", "py", "js", "ts", "html", "css",
             "go", "rs", "c", "cpp", "h", "java", "rb",
             "php", "sh", "json", "yaml", "toml":            return "Code"
        case "":                                              return "No Extension"
        default:                                             return ext.uppercased()
        }
    }
}
