import Foundation

class DiskScanner: ObservableObject {
    @Published var rootNode: FileNode?
    @Published var isScanning = false
    @Published var progress = ""
    @Published var error: String?
    @Published var scannedURL: URL?

    private var scanTask: Task<Void, Never>?

    func scan(url: URL) {
        scanTask?.cancel()
        DispatchQueue.main.async {
            self.isScanning = true
            self.error = nil
            self.rootNode = nil
            self.scannedURL = url
            self.progress = "Starting scan…"
        }

        scanTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                let node = try await self.buildTree(url: url)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.rootNode = node
                    self.isScanning = false
                    self.progress = ""
                }
            } catch is CancellationError {
                await MainActor.run { self.isScanning = false }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.isScanning = false
                }
            }
        }
    }

    func cancel() {
        scanTask?.cancel()
        DispatchQueue.main.async { self.isScanning = false }
    }

    private func buildTree(url: URL) async throws -> FileNode {
        try Task.checkCancellation()

        let resourceKeys: Set<URLResourceKey> = [.isDirectoryKey, .fileSizeKey,
                                                  .isSymbolicLinkKey, .isReadableKey]
        let values = try url.resourceValues(forKeys: resourceKeys)

        guard values.isReadable == true else {
            return FileNode(url: url, isDirectory: values.isDirectory ?? false)
        }

        if values.isSymbolicLink == true {
            let node = FileNode(url: url, isDirectory: false)
            node.size = Int64(values.fileSize ?? 0)
            return node
        }

        let isDirectory = values.isDirectory ?? false
        let node = FileNode(url: url, isDirectory: isDirectory)

        if isDirectory {
            await MainActor.run { [weak self] in
                self?.progress = "Scanning \(url.lastPathComponent)…"
            }

            let contents = (try? FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: Array(resourceKeys),
                options: [.skipsHiddenFiles]
            )) ?? []

            for childURL in contents {
                try Task.checkCancellation()
                let child = try await buildTree(url: childURL)
                node.children.append(child)
                node.size += child.size
            }
            node.children.sort { $0.size > $1.size }
        } else {
            node.size = Int64(values.fileSize ?? 0)
        }

        return node
    }

    // MARK: – Derived stats

    func allFiles() -> [FileNode] {
        var result: [FileNode] = []
        collectFiles(node: rootNode, into: &result)
        return result
    }

    private func collectFiles(node: FileNode?, into result: inout [FileNode]) {
        guard let node else { return }
        if !node.isDirectory { result.append(node) }
        for child in node.children { collectFiles(node: child, into: &result) }
    }

    func fileTypeStats() -> [FileTypeStats] {
        var groups: [String: (count: Int, size: Int64)] = [:]
        for file in allFiles() {
            let ext = file.fileExtension
            let cur = groups[ext] ?? (0, 0)
            groups[ext] = (cur.count + 1, cur.size + file.size)
        }
        return groups
            .map { FileTypeStats(ext: $0.key, count: $0.value.count, totalSize: $0.value.size) }
            .sorted { $0.totalSize > $1.totalSize }
    }

    func largestFiles(limit: Int = 100) -> [FileNode] {
        Array(allFiles().sorted { $0.size > $1.size }.prefix(limit))
    }
}
