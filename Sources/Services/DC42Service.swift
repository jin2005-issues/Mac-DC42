import Foundation
import Compression
import zlib

/// DC42 File Parser and Handler
/// 
/// Handles reading, writing, and conversion of DiskCopy 4.2 disk images
public final class DC42Service {
    
    public static let shared = DC42Service()
    
    private let magicBytes: [UInt8] = [0x43, 0x44, 0x34, 0x32] // "CD42"
    
    /// Maximum file size for processing (100 MB)
    private let maxFileSize: UInt64 = 100 * 1024 * 1024
    
    /// Chunk size for streaming operations (64 KB)
    private let chunkSize: Int = 64 * 1024
    
    /// Temporary directory for conversion operations
    private var tempDirectory: URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DC42Studio", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }
    
    private init() {}
    
    // MARK: - File Validation
    
    /// Validate if a file is a valid DC42 image
    public func validate(url: URL) throws -> DC42Image {
        // Check file size first
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let fileSize = attributes[.size] as? UInt64, fileSize > 0 else {
            throw DC42Error.invalidFormat
        }
        
        // Check if file is too large
        if fileSize > maxFileSize {
            throw DC42Error.fileTooLarge(maxFileSize)
        }
        
        // Read and parse header
        let header = try readHeader(from: url)
        
        // Verify magic number
        guard header.magic == magicBytes else {
            throw DC42Error.invalidMagic
        }
        
        // Calculate used space
        let usedSize = header.dataForkSize + header.resourceForkSize
        
        // Count files (estimate based on data fork size)
        var fileCount = 0
        if header.dataForkSize > 0 {
            // Rough estimate: assume average file size of 8KB
            fileCount = max(1, Int(header.dataForkSize / 8192))
        }
        
        return DC42Image(
            fileURL: url,
            volumeName: header.volumeName.trimmingCharacters(in: .controlCharacters),
            totalSize: fileSize,
            usedSize: usedSize,
            formatType: DC42FormatType(rawValue: header.version) ?? .standard,
            diskFormat: determineDiskFormat(imageSize: header.imageSize),
            dataForkSize: header.dataForkSize,
            resourceForkSize: header.resourceForkSize,
            creationDate: macDateToDate(header.creationDate),
            modificationDate: macDateToDate(header.modificationDate),
            comment: header.comment.trimmingCharacters(in: .controlCharacters),
            isValid: true,
            fileCount: fileCount
        )
    }
    
    // MARK: - Header Parsing
    
    /// Read and parse DC42 header from file
    private func readHeader(from url: URL) throws -> DC42Header {
        let fileHandle = try FileHandle(forReadingFrom: url)
        defer { try? fileHandle.close() }
        
        guard let headerData = try fileHandle.read(upToCount: DC42Header.headerSize),
              headerData.count == DC42Header.headerSize else {
            throw DC42Error.invalidHeader
        }
        
        return try parseHeader(headerData)
    }
    
    /// Parse DC42 header from raw data
    private func parseHeader(_ data: Data) throws -> DC42Header {
        guard data.count >= DC42Header.headerSize else {
            throw DC42Error.invalidHeader
        }
        
        var header = DC42Header()
        let bytes = [UInt8](data)
        
        // Magic number (4 bytes)
        header.magic = Array(bytes[0..<4])
        
        // Version (2 bytes, big-endian)
        header.version = UInt16(bytes[4]) | (UInt16(bytes[5]) << 8)
        
        // Volume name (64 bytes at offset 6)
        let volumeNameData = Data(bytes[6..<70])
        header.volumeName = String(data: volumeNameData, encoding: .macOSRoman)?.trimmingCharacters(in: .controlCharacters) ?? ""
        
        // Image size (8 bytes, big-endian)
        header.imageSize = readUInt64(bytes, offset: 70)
        
        // Media size (8 bytes)
        header.mediaSize = readUInt64(bytes, offset: 78)
        
        // Format flags (4 bytes)
        header.formatFlags = UInt32(bytes[86]) | (UInt32(bytes[87]) << 8) |
                            (UInt32(bytes[88]) << 16) | (UInt32(bytes[89]) << 24)
        
        // Checksum (4 bytes)
        header.checksum = UInt32(bytes[90]) | (UInt32(bytes[91]) << 8) |
                         (UInt32(bytes[92]) << 16) | (UInt32(bytes[93]) << 24)
        
        // Comment (128 bytes at offset 94)
        let commentData = Data(bytes[94..<222])
        header.comment = String(data: commentData, encoding: .macOSRoman)?.trimmingCharacters(in: .controlCharacters) ?? ""
        
        // Data fork offset (8 bytes)
        header.dataForkOffset = readUInt64(bytes, offset: 222)
        
        // Resource fork offset (8 bytes)
        header.resourceForkOffset = readUInt64(bytes, offset: 230)
        
        // Data fork size (8 bytes)
        header.dataForkSize = readUInt64(bytes, offset: 238)
        
        // Resource fork size (8 bytes)
        header.resourceForkSize = readUInt64(bytes, offset: 246)
        
        // Creation date (4 bytes)
        header.creationDate = UInt32(bytes[254]) | (UInt32(bytes[255]) << 8) |
                             (UInt32(bytes[256]) << 16) | (UInt32(bytes[257]) << 24)
        
        // Modification date (4 bytes)
        header.modificationDate = UInt32(bytes[258]) | (UInt32(bytes[259]) << 8) |
                                 (UInt32(bytes[260]) << 16) | (UInt32(bytes[261]) << 24)
        
        // Reserved (250 bytes)
        header.reserved = Array(bytes[262..<512])
        
        return header
    }
    
    // MARK: - Data Fork Reading (Streaming)
    
    /// Read data fork from DC42 image using streaming
    public func readDataFork(url: URL, progress: ((Double) -> Void)? = nil) throws -> Data {
        let header = try readHeader(from: url)
        
        // Validate offset and size
        guard header.dataForkOffset >= UInt64(DC42Header.headerSize),
              header.dataForkSize > 0,
              header.dataForkSize <= maxFileSize else {
            throw DC42Error.invalidFormat
        }
        
        let fileHandle = try FileHandle(forReadingFrom: url)
        defer { try? fileHandle.close() }
        
        // Seek to data fork
        try fileHandle.seek(toOffset: header.dataForkOffset)
        
        // Read data in chunks
        var data = Data()
        let totalSize = Int(header.dataForkSize)
        var bytesRead: Int = 0
        
        while bytesRead < totalSize {
            let chunk = min(chunkSize, totalSize - bytesRead)
            guard let chunkData = try fileHandle.read(upToCount: chunk) else {
                break
            }
            data.append(chunkData)
            bytesRead += chunkData.count
            
            // Report progress
            progress?(Double(bytesRead) / Double(totalSize))
        }
        
        return data
    }
    
    /// Stream data fork to a file (for large files)
    public func streamDataFork(from sourceURL: URL, to destinationURL: URL, progress: ((Double) -> Void)? = nil) throws {
        let header = try readHeader(from: sourceURL)
        
        guard header.dataForkSize > 0 else {
            throw DC42Error.invalidFormat
        }
        
        let sourceHandle = try FileHandle(forReadingFrom: sourceURL)
        let destHandle = try FileHandle(forWritingTo: destinationURL)
        
        defer {
            try? sourceHandle.close()
            try? destHandle.close()
        }
        
        try sourceHandle.seek(toOffset: header.dataForkOffset)
        
        var bytesWritten: UInt64 = 0
        let totalSize = header.dataForkSize
        
        while bytesWritten < totalSize {
            let remaining = Int(totalSize - bytesWritten)
            let chunk = min(chunkSize, remaining)
            
            guard let chunkData = try sourceHandle.read(upToCount: chunk) else {
                break
            }
            
            try destHandle.write(contentsOf: chunkData)
            bytesWritten += UInt64(chunkData.count)
            
            progress?(Double(bytesWritten) / Double(totalSize))
        }
    }
    
    /// Read resource fork from DC42 image
    public func readResourceFork(url: URL) throws -> Data {
        let header = try readHeader(from: url)
        
        // If no resource fork, return empty
        guard header.resourceForkOffset > 0, header.resourceForkSize > 0 else {
            return Data()
        }
        
        let fileHandle = try FileHandle(forReadingFrom: url)
        defer { try? fileHandle.close() }
        
        // Seek to resource fork
        try fileHandle.seek(toOffset: header.resourceForkOffset)
        
        // Read resource fork in chunks
        var data = Data()
        let totalSize = Int(header.resourceForkSize)
        var bytesRead: Int = 0
        
        while bytesRead < totalSize {
            let chunk = min(chunkSize, totalSize - bytesRead)
            guard let chunkData = try fileHandle.read(upToCount: chunk) else {
                break
            }
            data.append(chunkData)
            bytesRead += chunkData.count
        }
        
        return data
    }
    
    // MARK: - Image Creation
    
    /// Create a new DC42 image from data
    public func create(
        volumeName: String,
        dataFork: Data,
        resourceFork: Data? = nil,
        comment: String? = nil,
        to outputURL: URL
    ) throws {
        var header = DC42Header()
        
        // Set volume name (MacRoman encoded, 64 bytes max)
        header.volumeName = encodeMacRoman(volumeName, maxLength: 64)
        
        // Set sizes
        header.dataForkSize = UInt64(dataFork.count)
        header.resourceForkSize = UInt64(resourceFork?.count ?? 0)
        header.imageSize = UInt64(dataFork.count + (resourceFork?.count ?? 0))
        header.mediaSize = calculateMediaSize(for: header.imageSize)
        
        // Set dates
        let now = Date()
        header.creationDate = dateToMacDate(now)
        header.modificationDate = dateToMacDate(now)
        
        // Set comment
        if let comment = comment {
            header.comment = encodeMacRoman(comment, maxLength: 128)
        }
        
        // Calculate checksum
        header.checksum = calculateCRC32(data: dataFork)
        
        // Write file
        let fileHandle = try FileHandle(forWritingTo: outputURL)
        defer { try? fileHandle.close() }
        
        // Write header
        let headerData = serializeHeader(header)
        try fileHandle.write(contentsOf: headerData)
        
        // Write data fork
        try fileHandle.write(contentsOf: dataFork)
        
        // Write resource fork
        if let resourceFork = resourceFork, !resourceFork.isEmpty {
            try fileHandle.write(contentsOf: resourceFork)
        }
    }
    
    /// Create DC42 from folder with streaming support
    public func createFromFolder(
        sourceURL: URL,
        volumeName: String,
        progress: ((Double) -> Void)? = nil
    ) throws -> URL {
        let fileManager = FileManager.default
        
        // Create temp directory
        let tempDir = tempDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        // Create output file in temp directory
        let outputURL = tempDir.appendingPathComponent("output.dc42")
        
        // Get folder size first to validate
        let folderSize = try calculateFolderSize(at: sourceURL)
        if folderSize > maxFileSize {
            throw DC42Error.fileTooLarge(maxFileSize)
        }
        
        progress?(0.05)
        
        // Read folder contents
        let contents = try fileManager.contentsOfDirectory(
            at: sourceURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )
        
        // Calculate total size for progress
        let totalFiles = contents.count
        guard totalFiles > 0 else {
            throw DC42Error.invalidFormat
        }
        
        // Create output handle
        let outputHandle = try FileHandle(forWritingTo: outputURL)
        defer { try? outputHandle.close() }
        
        // Write header placeholder (will update later)
        let headerPlaceholder = Data(count: DC42Header.headerSize)
        try outputHandle.write(contentsOf: headerPlaceholder)
        
        var currentOffset = UInt64(DC42Header.headerSize)
        var totalDataWritten: UInt64 = 0
        var fileEntries: [(name: String, offset: UInt64, size: UInt64)] = []
        
        // Write each file
        for (index, fileURL) in contents.enumerated() {
            guard let fileData = try? Data(contentsOf: fileURL) else {
                continue
            }
            
            let fileOffset = currentOffset
            let fileSize = UInt64(fileData.count)
            
            // Align to 512 bytes
            let padding = (512 - (fileData.count % 512)) % 512
            
            // Record entry
            fileEntries.append((
                name: fileURL.lastPathComponent,
                offset: fileOffset,
                size: fileSize
            ))
            
            // Write file data
            try outputHandle.write(contentsOf: fileData)
            totalDataWritten += fileSize
            
            // Write padding
            if padding > 0 {
                try outputHandle.write(contentsOf: Data(count: padding))
                currentOffset += UInt64(padding)
            }
            
            currentOffset += fileSize
            
            // Update progress
            let fileProgress = Double(index + 1) / Double(totalFiles) * 0.8
            progress?(fileProgress)
        }
        
        // Update header with correct values
        progress?(0.9)
        
        // Read back and update header
        try outputHandle.synchronize()
        try outputHandle.seek(toOffset: 0)
        
        var header = DC42Header()
        header.magic = magicBytes
        header.version = 2
        header.volumeName = encodeMacRoman(volumeName, maxLength: 64)
        header.imageSize = totalDataWritten
        header.mediaSize = calculateMediaSize(for: totalDataWritten)
        header.dataForkOffset = UInt64(DC42Header.headerSize)
        header.dataForkSize = totalDataWritten
        header.resourceForkOffset = 0
        header.resourceForkSize = 0
        header.creationDate = dateToMacDate(Date())
        header.modificationDate = dateToMacDate(Date())
        header.checksum = calculateCRC32(data: Data())
        
        let headerData = serializeHeader(header)
        try outputHandle.write(contentsOf: headerData)
        try outputHandle.synchronize()
        
        progress?(1.0)
        return outputURL
    }
    
    // MARK: - Conversion
    
    /// Convert DC42 to another format
    public func convert(
        sourceURL: URL,
        to format: ConversionFormat,
        progress: ((Double) -> Void)? = nil
    ) throws -> URL {
        // Create temp directory for this conversion
        let conversionDir = tempDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: conversionDir, withIntermediateDirectories: true)
        
        progress?(0.1)
        
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        var outputURL: URL
        
        switch format {
        case .dc42:
            // Already DC42, just copy
            outputURL = conversionDir.appendingPathComponent("\(baseName).dc42")
            try streamFile(from: sourceURL, to: outputURL, progress: { p in
                progress?(0.1 + p * 0.9)
            })
            
        case .iso:
            // Convert to ISO
            outputURL = conversionDir.appendingPathComponent("\(baseName).iso")
            try convertDC42ToISO(source: sourceURL, destination: outputURL, progress: { p in
                progress?(0.1 + p * 0.9)
            })
            
        case .dmg:
            // Convert to DMG
            outputURL = conversionDir.appendingPathComponent("\(baseName).dmg")
            try streamDataFork(from: sourceURL, to: outputURL, progress: { p in
                progress?(0.1 + p * 0.9)
            })
            
        case .folder:
            // Extract to folder
            outputURL = conversionDir.appendingPathComponent(baseName, isDirectory: true)
            try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
            try extractToFolder(sourceURL: sourceURL, destination: outputURL, progress: { p in
                progress?(0.1 + p * 0.9)
            })
            
        case .img:
            // Extract as raw IMG
            outputURL = conversionDir.appendingPathComponent("\(baseName).img")
            try streamDataFork(from: sourceURL, to: outputURL, progress: { p in
                progress?(0.1 + p * 0.9)
            })
        }
        
        progress?(1.0)
        return outputURL
    }
    
    /// Convert DC42 to ISO format
    private func convertDC42ToISO(source: URL, destination: URL, progress: ((Double) -> Void)?) throws {
        // For HFS to ISO conversion, we extract the data fork
        // A full implementation would convert HFS filesystem to ISO9660
        try streamDataFork(from: source, to: destination, progress: progress)
    }
    
    /// Extract contents to folder
    private func extractToFolder(
        sourceURL: URL,
        destination: URL,
        progress: ((Double) -> Void)?
    ) throws {
        // Read data fork (simplified - just copy raw data)
        // A full implementation would parse HFS filesystem
        let dataFork = try readDataFork(url: sourceURL, progress: { p in
            progress?(p * 0.8)
        })
        
        // Save raw data to folder
        let outputFile = destination.appendingPathComponent("contents.dat")
        try dataFork.write(to: outputFile)
        
        progress?(1.0)
    }
    
    // MARK: - Stream File Copy
    
    /// Stream file copy with progress
    private func streamFile(from source: URL, to destination: URL, progress: ((Double) -> Void)?) throws {
        let sourceHandle = try FileHandle(forReadingFrom: source)
        let destHandle = try FileHandle(forWritingTo: destination)
        
        defer {
            try? sourceHandle.close()
            try? destHandle.close()
        }
        
        let attributes = try FileManager.default.attributesOfItem(atPath: source.path)
        let totalSize = (attributes[.size] as? UInt64) ?? 0
        
        var bytesWritten: UInt64 = 0
        
        while true {
            guard let chunk = try sourceHandle.read(upToCount: chunkSize) else {
                break
            }
            
            if chunk.isEmpty {
                break
            }
            
            try destHandle.write(contentsOf: chunk)
            bytesWritten += UInt64(chunk.count)
            
            if totalSize > 0 {
                progress?(Double(bytesWritten) / Double(totalSize))
            }
        }
        
        try destHandle.synchronize()
    }
    
    // MARK: - Helper Methods
    
    /// Read UInt64 from bytes (big-endian)
    private func readUInt64(_ bytes: [UInt8], offset: Int) -> UInt64 {
        return UInt64(bytes[offset]) |
               (UInt64(bytes[offset + 1]) << 8) |
               (UInt64(bytes[offset + 2]) << 16) |
               (UInt64(bytes[offset + 3]) << 24) |
               (UInt64(bytes[offset + 4]) << 32) |
               (UInt64(bytes[offset + 5]) << 40) |
               (UInt64(bytes[offset + 6]) << 48) |
               (UInt64(bytes[offset + 7]) << 56)
    }
    
    /// Write UInt64 to bytes (big-endian)
    private func writeUInt64(_ value: UInt64) -> [UInt8] {
        return [
            UInt8(value & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 32) & 0xFF),
            UInt8((value >> 40) & 0xFF),
            UInt8((value >> 48) & 0xFF),
            UInt8((value >> 56) & 0xFF)
        ]
    }
    
    /// Serialize DC42 header to Data
    private func serializeHeader(_ header: DC42Header) -> Data {
        var data = Data(capacity: DC42Header.headerSize)
        
        // Magic (4 bytes)
        data.append(contentsOf: header.magic)
        
        // Version (2 bytes)
        data.append(UInt8(header.version & 0xFF))
        data.append(UInt8((header.version >> 8) & 0xFF))
        
        // Volume name (64 bytes)
        data.append(contentsOf: encodeMacRoman(header.volumeName, maxLength: 64))
        
        // Image size (8 bytes)
        data.append(contentsOf: writeUInt64(header.imageSize))
        
        // Media size (8 bytes)
        data.append(contentsOf: writeUInt64(header.mediaSize))
        
        // Format flags (4 bytes)
        data.append(UInt8(header.formatFlags & 0xFF))
        data.append(UInt8((header.formatFlags >> 8) & 0xFF))
        data.append(UInt8((header.formatFlags >> 16) & 0xFF))
        data.append(UInt8((header.formatFlags >> 24) & 0xFF))
        
        // Checksum (4 bytes)
        data.append(UInt8(header.checksum & 0xFF))
        data.append(UInt8((header.checksum >> 8) & 0xFF))
        data.append(UInt8((header.checksum >> 16) & 0xFF))
        data.append(UInt8((header.checksum >> 24) & 0xFF))
        
        // Comment (128 bytes)
        data.append(contentsOf: encodeMacRoman(header.comment, maxLength: 128))
        
        // Data fork offset (8 bytes)
        data.append(contentsOf: writeUInt64(header.dataForkOffset))
        
        // Resource fork offset (8 bytes)
        data.append(contentsOf: writeUInt64(header.resourceForkOffset))
        
        // Data fork size (8 bytes)
        data.append(contentsOf: writeUInt64(header.dataForkSize))
        
        // Resource fork size (8 bytes)
        data.append(contentsOf: writeUInt64(header.resourceForkSize))
        
        // Creation date (4 bytes)
        data.append(UInt8(header.creationDate & 0xFF))
        data.append(UInt8((header.creationDate >> 8) & 0xFF))
        data.append(UInt8((header.creationDate >> 16) & 0xFF))
        data.append(UInt8((header.creationDate >> 24) & 0xFF))
        
        // Modification date (4 bytes)
        data.append(UInt8(header.modificationDate & 0xFF))
        data.append(UInt8((header.modificationDate >> 8) & 0xFF))
        data.append(UInt8((header.modificationDate >> 16) & 0xFF))
        data.append(UInt8((header.modificationDate >> 24) & 0xFF))
        
        // Reserved (250 bytes to reach 512 total)
        data.append(contentsOf: [UInt8](repeating: 0, count: DC42Header.headerSize - data.count))
        
        return data
    }
    
    /// Encode string to MacRoman with fixed length
    private func encodeMacRoman(_ string: String, maxLength: Int) -> [UInt8] {
        var bytes = [UInt8](string.data(using: .macOSRoman) ?? Data())
        if bytes.count > maxLength {
            bytes = Array(bytes.prefix(maxLength))
        }
        bytes.append(contentsOf: [UInt8](repeating: 0, count: max(0, maxLength - bytes.count)))
        return bytes
    }
    
    /// Convert Mac date (seconds since 1904) to Date
    private func macDateToDate(_ macDate: UInt32) -> Date? {
        let secondsSince1904 = Double(macDate)
        let secondsSince1970 = secondsSince1904 - 2082844800
        return Date(timeIntervalSince1970: secondsSince1970)
    }
    
    /// Convert Date to Mac date
    private func dateToMacDate(_ date: Date) -> UInt32 {
        let secondsSince1970 = date.timeIntervalSince1970
        let secondsSince1904 = secondsSince1970 + 2082844800
        return UInt32(max(0, secondsSince1904))
    }
    
    /// Calculate CRC32 checksum
    private func calculateCRC32(data: Data) -> UInt32 {
        guard !data.isEmpty else { return 0 }
        let bytes = [UInt8](data)
        return bytes.withUnsafeBufferPointer { buffer -> UInt32 in
            let crc = crc32(0, buffer.baseAddress, uInt(data.count))
            return UInt32(crc)
        }
    }
    
    /// Calculate media size (aligned to 512 bytes)
    private func calculateMediaSize(for dataSize: UInt64) -> UInt64 {
        let blockSize: UInt64 = 512
        let blocks = (dataSize + blockSize - 1) / blockSize
        return blocks * blockSize
    }
    
    /// Determine disk format based on size
    private func determineDiskFormat(imageSize: UInt64) -> DC42DiskFormat {
        switch imageSize {
        case 0..<500_000: return .floppy400KB
        case 500_000..<1_000_000: return .floppy800KB
        case 1_000_000..<1_600_000: return .floppy1440KB
        case 1_600_000..<3_000_000: return .floppy2880KB
        default: return .hardDisk
        }
    }
    
    /// Calculate total size of folder contents
    private func calculateFolderSize(at url: URL) throws -> UInt64 {
        let fileManager = FileManager.default
        var totalSize: UInt64 = 0
        
        let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        
        while let fileURL = enumerator?.nextObject() as? URL {
            let resourceValues = try fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            if resourceValues.isRegularFile == true, let size = resourceValues.fileSize {
                totalSize += UInt64(size)
            }
        }
        
        return totalSize
    }
    
    // MARK: - Cleanup
    
    /// Clean up temporary files
    public func cleanup() {
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: tempDirectory)
    }
}

// MARK: - DC42 Errors

public enum DC42Error: LocalizedError {
    case invalidHeader
    case invalidMagic
    case invalidFormat
    case readFailed
    case writeFailed
    case checksumMismatch
    case unsupportedVersion
    case fileTooLarge(UInt64)
    
    public var errorDescription: String? {
        switch self {
        case .invalidHeader:
            return "Invalid DC42 header"
        case .invalidMagic:
            return "Not a valid DC42 file (missing CD42 magic)"
        case .invalidFormat:
            return "Invalid DC42 format"
        case .readFailed:
            return "Failed to read DC42 file"
        case .writeFailed:
            return "Failed to write DC42 file"
        case .checksumMismatch:
            return "Checksum mismatch - file may be corrupted"
        case .unsupportedVersion:
            return "Unsupported DC42 version"
        case .fileTooLarge(let max):
            let maxMB = max / (1024 * 1024)
            return "File too large. Maximum supported size is \(maxMB) MB"
        }
    }
}
