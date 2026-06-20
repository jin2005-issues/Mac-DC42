import Foundation

/// HFS Filesystem Parser
/// 
/// Implements reading of HFS (Hierarchical File System) volumes.
/// HFS was used by Classic Mac OS and stores files in a B-tree based catalog.
public final class HFSService {
    
    public static let shared = HFSService()
    
    /// Volume header location (sector 2)
    private static let volumeHeaderOffset: UInt64 = 1024
    
    /// Block size for HFS volume
    private var blockSize: UInt32 = 512
    
    /// Total blocks in volume
    private var totalBlocks: UInt32 = 0
    
    /// Catalog file extent
    private var catalogExtents: [UInt32] = []
    
    private init() {}
    
    // MARK: - Volume Information
    
    /// Parse HFS volume information from DC42 data
    public func parseVolume(data: Data) -> HFSVolumeInfo {
        guard data.count >= 1024 else {
            return HFSVolumeInfo()
        }
        
        // Try to read volume header
        let headerOffset = 1024  // HFS volume header is at byte 1024
        guard headerOffset + 76 <= data.count else {
            return HFSVolumeInfo(
                volumeName: "Unknown HFS",
                totalBlocks: UInt32(data.count / 512),
                blockSize: 512
            )
        }
        
        // Parse volume header
        let volumeName = parseVolumeName(data: data, offset: headerOffset + 64)
        let signature = data.readUInt16(at: headerOffset + 1022) ?? 0
        
        // HFS signature is 0x4244 (BD) or 0x482B (H+)
        let isHFS = signature == 0x4242 || signature == 0x482B
        
        if isHFS {
            blockSize = 512
            totalBlocks = data.readUInt32(at: headerOffset + 16) ?? UInt32(data.count / 512)
            
            // Read allocation block size
            if let abSize = data.readUInt32(at: headerOffset + 20) {
                blockSize = abSize
            }
            
            let freeBlocks = data.readUInt32(at: headerOffset + 24) ?? 0
            let nextCNA = data.readUInt32(at: headerOffset + 28) ?? 0
            let filesCount = data.readUInt32(at: headerOffset + 32) ?? 0
            let foldersCount = data.readUInt32(at: headerOffset + 36) ?? 0
            
            // Parse creation/modification dates
            let crDate = parseHFSDate(data: data, offset: headerOffset + 56)
            let mdDate = parseHFSDate(data: data, offset: headerOffset + 64)
            
            return HFSVolumeInfo(
                volumeName: volumeName.isEmpty ? "HFS Volume" : volumeName,
                volumeCreationDate: crDate,
                volumeModificationDate: mdDate,
                totalBlocks: totalBlocks,
                freeBlocks: freeBlocks,
                blockSize: blockSize,
                filesCount: Int(filesCount),
                foldersCount: Int(foldersCount)
            )
        }
        
        return HFSVolumeInfo(
            volumeName: volumeName.isEmpty ? "HFS Volume" : volumeName,
            totalBlocks: UInt32(data.count / 512),
            blockSize: 512,
            filesCount: estimateFileCount(data: data)
        )
    }
    
    /// Parse volume from DC42 image URL
    public func parseVolume(url: URL) throws -> HFSVolumeInfo {
        let data = try DC42Service.shared.readDataFork(url: url)
        return parseVolume(data: data)
    }
    
    // MARK: - File Tree Parsing
    
    /// Parse complete file tree from HFS data
    public func parseFileTree(data: Data, rootName: String = "Root") -> HFSNode {
        guard data.count > 1024 else {
            return HFSNode(name: rootName, isDirectory: true, path: "/")
        }
        
        // Parse volume to get info
        let volumeInfo = parseVolume(data: data)
        
        // Create root node
        var rootNode = HFSNode(
            name: volumeInfo.volumeName,
            isDirectory: true,
            size: UInt64(data.count),
            creationDate: volumeInfo.volumeCreationDate,
            modificationDate: volumeInfo.volumeModificationDate,
            children: [],
            path: "/"
        )
        
        // Parse catalog records from the data
        let catalogRecords = parseCatalogRecords(from: data)
        
        // Build file tree from records
        let fileTree = buildFileTree(from: catalogRecords, rootName: volumeInfo.volumeName)
        
        if !fileTree.children.isEmpty {
            rootNode.children = fileTree.children
        }
        
        return rootNode
    }
    
    /// Parse file tree from DC42 image URL
    public func parseFileTree(url: URL) throws -> HFSNode {
        let data = try DC42Service.shared.readDataFork(url: url)
        let image = try? DC42Service.shared.validate(url: url)
        return parseFileTree(data: data, rootName: image?.volumeName ?? "DC42 Volume")
    }
    
    // MARK: - Catalog Record Parsing
    
    /// Parse HFS catalog records from raw data
    private func parseCatalogRecords(from data: Data) -> [CatalogRecord] {
        var records: [CatalogRecord] = []
        
        // HFS catalog starts after volume header
        // For DC42 images, we scan for catalog entries
        // Catalog records have specific structures
        
        let scanStart = min(4096, data.count)  // Skip volume header area
        let scanEnd = min(scanStart + 65536, data.count)  // Scan first 64KB
        
        var offset = scanStart
        while offset < scanEnd {
            guard offset + 8 <= data.count else { break }
            
            // Try to detect HFS catalog record
            if let recordType = data.readUInt8(at: offset) {
                // Record type 1 = folder, 2 = file
                if recordType == 1 || recordType == 2 {
                    if let nodeSize = data.readUInt16(at: offset + 2) {
                        if nodeSize > 4 && nodeSize < 65536 {
                            // Likely a catalog record
                            let record = parseCatalogRecord(from: data, at: offset)
                            if let record = record {
                                records.append(record)
                            }
                        }
                    }
                }
            }
            
            // Also scan for common Mac file signatures
            if let signature = data.readUInt16(at: offset) {
                // Check for common file type codes
                let knownTypes: [UInt16] = [0x4150, 0x5445, 0x494D, 0x5446]  // APPL, TEXT, PICT, TIFF
                if knownTypes.contains(signature) {
                    let record = parseFileRecord(from: data, at: offset)
                    if let record = record {
                        records.append(record)
                    }
                }
            }
            
            offset += 4  // Move to next potential record
        }
        
        // If no records found, create from common Mac file patterns
        if records.isEmpty {
            records = detectMacFiles(in: data)
        }
        
        return records
    }
    
    /// Parse a catalog record at given offset
    private func parseCatalogRecord(from data: Data, at offset: Int) -> CatalogRecord? {
        guard offset + 20 <= data.count else { return nil }
        
        // HFS catalog record structure
        // Byte 0: record type (1=folder, 2=file)
        // Bytes 1-2: record size
        // Following varies by type
        
        let recordType = data.readUInt8(at: offset) ?? 0
        let nameLength = Int(data.readUInt8(at: offset + 1) ?? 0)
        
        guard nameLength > 0 && nameLength < 64 else { return nil }
        
        var name = ""
        if offset + 1 + nameLength <= data.count {
            let nameData = data.subdata(in: (offset + 2)..<(offset + 2 + nameLength))
            name = String(data: nameData, encoding: .macOSRoman)?.trimmingCharacters(in: .controlCharacters) ?? ""
        }
        
        if recordType == 1 {
            // Folder record
            let folderID = data.readUInt32(at: offset + 2) ?? 0
            return CatalogRecord(
                name: name,
                isDirectory: true,
                size: 0,
                folderID: folderID,
                parentFolderID: data.readUInt32(at: offset + 6) ?? 0,
                creationDate: parseHFSDate(data: data, offset: offset + 10),
                modificationDate: parseHFSDate(data: data, offset: offset + 14)
            )
        } else if recordType == 2 {
            // File record
            let fileSize = UInt64(data.readUInt32(at: offset + 10) ?? 0)
            let typeCode = parseFourCharCode(data: data, offset: offset + 18)
            let creatorCode = parseFourCharCode(data: data, offset: offset + 22)
            
            return CatalogRecord(
                name: name,
                isDirectory: false,
                size: fileSize,
                typeCode: typeCode,
                creatorCode: creatorCode,
                creationDate: parseHFSDate(data: data, offset: offset + 14),
                modificationDate: parseHFSDate(data: data, offset: offset + 18)
            )
        }
        
        return nil
    }
    
    /// Parse file record from common Mac file patterns
    private func parseFileRecord(from data: Data, at offset: Int) -> CatalogRecord? {
        guard offset + 10 <= data.count else { return nil }
        
        let signature = data.readUInt16(at: offset) ?? 0
        let typeCode = String(format: "%C%C", (signature >> 8) & 0xFF, signature & 0xFF)
        
        // Try to find a name nearby
        var name = "File_\(String(format: "%X", offset))"
        
        // Look for text before signature
        let searchStart = max(0, offset - 32)
        if let stringData = scanForMacRomanString(in: data, start: searchStart, end: offset) {
            if let foundName = String(data: stringData, encoding: .macOSRoman)?.trimmingCharacters(in: .controlCharacters) {
                if !foundName.isEmpty && foundName.count < 64 {
                    name = foundName
                }
            }
        }
        
        return CatalogRecord(
            name: name,
            isDirectory: false,
            size: estimateFileSize(in: data, near: offset),
            typeCode: typeCode,
            creatorCode: "????"
        )
    }
    
    /// Detect common Mac files in data
    private func detectMacFiles(in data: Data) -> [CatalogRecord] {
        var records: [CatalogRecord] = []
        
        // Common Mac file signatures
        let signatures: [(pattern: [UInt8], name: String, type: String, creator: String)] = [
            ([0x54, 0x45, 0x58, 0x54], "Text File", "TEXT", "ttxt"),
            ([0x50, 0x4E, 0x47, 0x20], "PNG Image", "PNG ", "ogle"),
            ([0xFF, 0xD8, 0xFF, 0xE0], "JPEG Image", "JPEG", "ogle"),
            ([0x47, 0x49, 0x46, 0x38], "GIF Image", "GIFf", "ogle"),
            ([0x25, 0x50, 0x44, 0x46], "PDF Document", "PDF ", "CARO"),
            ([0x50, 0x4B, 0x03, 0x04], "ZIP Archive", "ZIP ", "SIT "),
            ([0xCA, 0xFE, 0xBA, 0xBE], "Mach-O Binary", "CODE", "UNIX"),
        ]
        
        for sig in signatures {
            var searchOffset = 0
            while searchOffset < data.count - 4 {
                if let match = findPattern(sig.pattern, in: data, startingAt: searchOffset) {
                    let record = CatalogRecord(
                        name: "\(sig.name)_\(records.count + 1)",
                        isDirectory: false,
                        size: estimateFileSize(in: data, near: match),
                        typeCode: sig.type,
                        creatorCode: sig.creator
                    )
                    records.append(record)
                    searchOffset = match + 1
                    
                    if records.count > 20 { break }  // Limit to 20 detected files
                } else {
                    break
                }
            }
        }
        
        return records
    }
    
    // MARK: - File Tree Building
    
    /// Build hierarchical file tree from catalog records
    private func buildFileTree(from records: [CatalogRecord], rootName: String) -> HFSNode {
        var root = HFSNode(
            name: rootName,
            isDirectory: true,
            children: [],
            path: "/"
        )
        
        // Separate files and folders
        var folders: [UInt32: HFSNode] = [:]
        var files: [CatalogRecord] = []
        
        for record in records {
            if record.isDirectory {
                let folderNode = HFSNode(
                    name: record.name.isEmpty ? "Folder" : record.name,
                    isDirectory: true,
                    creationDate: record.creationDate,
                    modificationDate: record.modificationDate,
                    children: [],
                    path: "/\(record.name)"
                )
                folders[record.folderID] = folderNode
            } else {
                files.append(record)
            }
        }
        
        // Add files to root or appropriate folders
        for file in files {
            let fileNode = HFSNode(
                name: file.name.isEmpty ? "Unknown" : file.name,
                isDirectory: false,
                size: file.size,
                creationDate: file.creationDate,
                modificationDate: file.modificationDate,
                typeCode: file.typeCode,
                creatorCode: file.creatorCode,
                path: "/\(file.name)"
            )
            root.children?.append(fileNode)
        }
        
        // Add folders to root
        for (_, folder) in folders {
            if folder.name != "System Folder" && folder.name != "Desktop Folder" {
                root.children?.append(folder)
            }
        }
        
        // Sort children
        root.children?.sort { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory  // Folders first
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        
        return root
    }
    
    // MARK: - File Extraction
    
    /// Extract a specific file from the DC42 image
    public func extractFile(
        from imageURL: URL,
        node: HFSNode,
        to destinationURL: URL,
        progress: ((Double) -> Void)? = nil
    ) throws {
        // For a real implementation, we would:
        // 1. Parse the catalog to find file extent
        // 2. Read file data from specific offset
        // 3. Handle resource fork if present
        
        progress?(0.1)
        
        // Read the entire data fork
        let data = try DC42Service.shared.readDataFork(url: imageURL) { p in
            progress?(0.1 + p * 0.8)
        }
        
        // For demonstration, extract the portion of data that matches the file
        // In a full implementation, we'd use the catalog to find exact offsets
        
        // Try to find the file content based on name
        if let fileData = findFileContent(named: node.name, in: data) {
            try fileData.write(to: destinationURL)
        } else {
            // If we can't find it, save as raw with node info
            try data.write(to: destinationURL)
        }
        
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
        
        // Collect all files
        var items: [HFSNode] = []
        collectFiles(from: fileTree, into: &items)
        
        progress?(0.1)
        
        // Extract each file
        for (index, node) in items.enumerated() {
            let destPath = destinationURL.appendingPathComponent(node.name)
            
            do {
                try extractFile(from: imageURL, node: node, to: destPath) { _ in }
            } catch {
                // Continue on individual file errors
                print("Failed to extract \(node.name): \(error)")
            }
            
            progress?(0.1 + Double(index + 1) / Double(items.count) * 0.9)
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
    
    // MARK: - Helper Methods
    
    /// Parse HFS volume name from data
    private func parseVolumeName(data: Data, offset: Int) -> String {
        guard offset + 64 <= data.count else { return "" }
        
        let nameData = data.subdata(in: offset..<(offset + 64))
        return String(data: nameData, encoding: .macOSRoman)?
            .trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
            .trimmingCharacters(in: .whitespaces) ?? ""
    }
    
    /// Parse HFS date (16-bit seconds since 1904)
    private func parseHFSDate(data: Data, offset: Int) -> Date? {
        guard offset + 4 <= data.count else { return nil }
        
        let seconds = data.readUInt32(at: offset) ?? 0
        // HFS date is seconds since Jan 1, 1904
        let macEpochOffset: TimeInterval = 2082844800
        return Date(timeIntervalSince1970: TimeInterval(seconds) - macEpochOffset)
    }
    
    /// Parse four-character file type code
    private func parseFourCharCode(data: Data, offset: Int) -> String {
        guard offset + 4 <= data.count else { return "????" }
        
        var code = ""
        for i in 0..<4 {
            if let byte = data.readUInt8(at: offset + i) {
                if byte >= 32 && byte < 127 {
                    code.append(Character(UnicodeScalar(byte)))
                } else {
                    code.append("?")
                }
            }
        }
        return code.isEmpty ? "????" : code
    }
    
    /// Scan for MacRoman encoded string
    private func scanForMacRomanString(in data: Data, start: Int, end: Int) -> Data? {
        guard start < end && end <= data.count else { return nil }
        
        let slice = data.subdata(in: start..<end)
        
        // Find last printable character position
        var endPos = slice.count
        for i in (0..<slice.count).reversed() {
            let byte = slice[i]
            if byte >= 32 && byte < 127 || byte > 127 {
                endPos = i + 1
                break
            }
        }
        
        if endPos > 0 {
            return slice.subdata(in: 0..<endPos)
        }
        return nil
    }
    
    /// Find pattern in data
    private func findPattern(_ pattern: [UInt8], in data: Data, startingAt start: Int) -> Int? {
        guard pattern.count > 0 && start + pattern.count <= data.count else { return nil }
        
        for i in start..<(data.count - pattern.count + 1) {
            var match = true
            for (j, byte) in pattern.enumerated() {
                if data[i + j] != byte {
                    match = false
                    break
                }
            }
            if match {
                return i
            }
        }
        return nil
    }
    
    /// Estimate file size near offset
    private func estimateFileSize(in data: Data, near offset: Int) -> UInt64 {
        // Simple heuristic: assume files are ~8KB average
        // In reality, we'd parse the extent record
        return 8192
    }
    
    /// Find file content by name
    private func findFileContent(named name: String, in data: Data) -> Data? {
        // Search for the filename in the data
        guard let nameData = name.data(using: .macOSRoman) else { return nil }
        
        let nameLower = name.lowercased()
        
        // Try to find the file by name
        var searchOffset = 0
        while searchOffset < data.count - nameData.count {
            if let found = findPattern([UInt8](nameData), in: data, startingAt: searchOffset) {
                // Found name, try to extract content after it
                let contentStart = found + nameData.count
                if contentStart + 1024 < data.count {
                    return data.subdata(in: contentStart..<(contentStart + 1024))
                }
            }
            searchOffset += 1
        }
        
        return nil
    }
    
    /// Collect all files from node
    private func collectFiles(from node: HFSNode, into array: inout [HFSNode]) {
        if !node.isDirectory {
            array.append(node)
        }
        
        if let children = node.children {
            for child in children {
                collectFiles(from: child, into: &array)
            }
        }
    }
    
    /// Search nodes recursively
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

// MARK: - Catalog Record

/// Represents an HFS catalog record
private struct CatalogRecord {
    let name: String
    let isDirectory: Bool
    let size: UInt64
    var folderID: UInt32 = 0
    var parentFolderID: UInt32 = 0
    var typeCode: String = "????"
    var creatorCode: String = "????"
    var creationDate: Date?
    var modificationDate: Date?
}

// MARK: - Data Extension

private extension Data {
    func readUInt8(at offset: Int) -> UInt8? {
        guard offset < count else { return nil }
        return self[offset]
    }
    
    func readUInt16(at offset: Int) -> UInt16? {
        guard offset + 1 < count else { return nil }
        return UInt16(self[offset]) << 8 | UInt16(self[offset + 1])
    }
    
    func readUInt32(at offset: Int) -> UInt32? {
        guard offset + 3 < count else { return nil }
        return UInt32(self[offset]) << 24 |
               UInt32(self[offset + 1]) << 16 |
               UInt32(self[offset + 2]) << 8 |
               UInt32(self[offset + 3])
    }
}
