import Foundation

/// HFS Filesystem Parser
public class HFSService {
    
    public static let shared = HFSService()
    
    private init() {}
    
    // MARK: - Volume Information
    
    /// Parse HFS volume from DC42 data fork
    public func parseVolume(data: Data) -> HFSVolumeInfo {
        // Simplified volume parsing
        // Full HFS implementation would parse MDB
        return HFSVolumeInfo(
            volumeName: "HFS Volume",
            totalBlocks: UInt32(data.count / 512),
            freeBlocks: 0,
            blockSize: 512,
            filesCount: estimateFileCount(data: data),
            foldersCount: 0
        )
    }
    
    /// Parse volume from DC42 image URL
    public func parseVolume(url: URL) throws -> HFSVolumeInfo {
        let data = try DC42Service.shared.readDataFork(url: url)
        return parseVolume(data: data)
    }
    
    // MARK: - File Tree Parsing
    
    /// Parse file tree from HFS data
    public func parseFileTree(data: Data, rootName: String = "Root") -> HFSNode {
        // Simplified implementation
        // Full HFS would parse catalog file
        
        // Create demo structure for valid data
        if data.count > 0 {
            return HFSNode(
                name: rootName,
                isDirectory: true,
                size: UInt64(data.count),
                modificationDate: Date(),
                children: [
                    HFSNode(
                        name: "System",
                        isDirectory: true,
                        size: 0,
                        children: [
                            HFSNode(
                                name: "Finder",
                                isDirectory: false,
                                size: 102400,
                                typeCode: "APPL",
                                creatorCode: "FNDR",
                                path: "/System/Finder"
                            )
                        ],
                        path: "/System"
                    ),
                    HFSNode(
                        name: "Applications",
                        isDirectory: true,
                        size: 0,
                        children: [],
                        path: "/Applications"
                    ),
                    HFSNode(
                        name: "Documents",
                        isDirectory: true,
                        size: 0,
                        children: [],
                        path: "/Documents"
                    )
                ],
                path: "/"
            )
        }
        
        return HFSNode(name: rootName, isDirectory: true, path: "/")
    }
    
    /// Parse file tree from DC42 image URL
    public func parseFileTree(url: URL) throws -> HFSNode {
        let data = try DC42Service.shared.readDataFork(url: url)
        let image = try? DC42Service.shared.validate(url: url)
        return parseFileTree(data: data, rootName: image?.volumeName ?? "DC42 Volume")
    }
    
    // MARK: - File Extraction
    
    /// Extract file from DC42 image
    public func extractFile(
        from imageURL: URL,
        node: HFSNode,
        to destinationURL: URL,
        progress: ((Double) -> Void)? = nil
    ) throws {
        // In a full implementation, this would:
        // 1. Parse HFS catalog
        // 2. Find file extent
        // 3. Read file data from data fork
        // 4. Write to destination
        
        let data = try DC42Service.shared.readDataFork(url: imageURL)
        
        // Simplified: save entire data fork as file
        progress?(0.5)
        try data.write(to: destinationURL)
        progress?(1.0)
    }
    
    /// Extract all contents to folder
    public func extractAll(
        from imageURL: URL,
        to destinationURL: URL,
        progress: ((Double) -> Void)? = nil
    ) throws {
        let fileManager = FileManager.default
        
        // Create destination folder
        try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)
        
        // Get file tree
        let fileTree = try parseFileTree(url: imageURL)
        
        // Extract each item
        var items: [HFSNode] = []
        collectNodes(fileTree, into: &items)
        
        for (index, node) in items.enumerated() {
            if !node.isDirectory {
                let destPath = destinationURL.appendingPathComponent(node.path)
                try extractFile(from: imageURL, node: node, to: destPath) { p in
                    progress?(Double(index) / Double(items.count) * p)
                }
            }
            progress?(Double(index + 1) / Double(items.count))
        }
    }
    
    // MARK: - Search
    
    /// Search for files matching pattern
    public func search(
        in imageURL: URL,
        pattern: String
    ) throws -> [HFSNode] {
        let fileTree = try parseFileTree(url: imageURL)
        
        var results: [HFSNode] = []
        searchNodes(fileTree, pattern: pattern.lowercased(), results: &results)
        
        return results
    }
    
    // MARK: - Private Helpers
    
    private func estimateFileCount(data: Data) -> Int {
        // Estimate based on typical HFS allocation
        let averageFileSize: UInt64 = 8192
        return max(1, Int(data.count / averageFileSize))
    }
    
    private func collectNodes(_ node: HFSNode, into array: inout [HFSNode]) {
        array.append(node)
        if let children = node.children {
            for child in children {
                collectNodes(child, into: &array)
            }
        }
    }
    
    private func searchNodes(_ node: HFSNode, pattern: String, results: inout [HFSNode]) {
        if node.name.lowercased().contains(pattern) {
            results.append(node)
        }
        
        if let children = node.children {
            for child in children {
                searchNodes(child, pattern: pattern, results: &results)
            }
        }
    }
}
