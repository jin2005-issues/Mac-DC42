import Foundation
import Compression

/// DC42 File Parser and Handler
public class DC42Service {
    
    public static let shared = DC42Service()
    
    private let magicBytes: [UInt8] = [0x43, 0x44, 0x34, 0x32] // "CD42"
    
    private init() {}
    
    // MARK: - File Validation
    
    /// Validate if a file is a valid DC42 image
    public func validate(url: URL) throws -> DC42Image {
        let fileHandle = try FileHandle(forReadingFrom: url)
        defer { try? fileHandle.close() }
        
        // Read header
        guard let headerData = try fileHandle.read(upToCount: DC42Header.headerSize),
              headerData.count == DC42Header.headerSize else {
            throw DC42Error.invalidHeader
        }
        
        let header = try parseHeader(headerData)
        
        // Verify magic number
        guard header.magic == magicBytes else {
            throw DC42Error.invalidMagic
        }
        
        // Get file attributes
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = attributes[.size] as? UInt64 ?? 0
        
        // Calculate used space
        let usedSize = header.dataForkSize + header.resourceForkSize
        
        // Count files (if possible)
        var fileCount = 0
        if header.dataForkSize > 0 {
            fileCount = 1
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
    
    private func parseHeader(_ data: Data) throws -> DC42Header {
        var header = DC42Header()
        
        let bytes = [UInt8](data)
        guard bytes.count >= DC42Header.headerSize else {
            throw DC42Error.invalidHeader
        }
        
        // Magic number
        header.magic = Array(bytes[0..<4])
        
        // Version
        header.version = UInt16(bytes[4]) | (UInt16(bytes[5]) << 8)
        
        // Volume name (64 bytes at offset 6)
        let volumeNameData = Data(bytes[6..<70])
        header.volumeName = String(data: volumeNameData, encoding: .macOSRoman) ?? ""
        
        // Image size
        header.imageSize = readUInt64(bytes, offset: 70)
        
        // Media size
        header.mediaSize = readUInt64(bytes, offset: 78)
        
        // Format flags
        header.formatFlags = UInt32(bytes[86]) | (UInt32(bytes[87]) << 8) |
                            (UInt32(bytes[88]) << 16) | (UInt32(bytes[89]) << 24)
        
        // Checksum
        header.checksum = UInt32(bytes[90]) | (UInt32(bytes[91]) << 8) |
                         (UInt32(bytes[92]) << 16) | (UInt32(bytes[93]) << 24)
        
        // Comment (128 bytes at offset 94)
        let commentData = Data(bytes[94..<222])
        header.comment = String(data: commentData, encoding: .macOSRoman) ?? ""
        
        // Data fork offset
        header.dataForkOffset = readUInt64(bytes, offset: 222)
        
        // Resource fork offset
        header.resourceForkOffset = readUInt64(bytes, offset: 230)
        
        // Data fork size
        header.dataForkSize = readUInt64(bytes, offset: 238)
        
        // Resource fork size
        header.resourceForkSize = readUInt64(bytes, offset: 246)
        
        // Creation date
        header.creationDate = UInt32(bytes[254]) | (UInt32(bytes[255]) << 8) |
                             (UInt32(bytes[256]) << 16) | (UInt32(bytes[257]) << 24)
        
        // Modification date
        header.modificationDate = UInt32(bytes[258]) | (UInt32(bytes[259]) << 8) |
                                 (UInt32(bytes[260]) << 16) | (UInt32(bytes[261]) << 24)
        
        // Reserved
        header.reserved = Array(bytes[262..<512])
        
        return header
    }
    
    // MARK: - Data Fork Reading
    
    /// Read data fork from DC42 image
    public func readDataFork(url: URL) throws -> Data {
        let fileHandle = try FileHandle(forReadingFrom: url)
        defer { try? fileHandle.close() }
        
        // Read header
        guard let headerData = try fileHandle.read(upToCount: DC42Header.headerSize) else {
            throw DC42Error.invalidHeader
        }
        
        let header = try parseHeader(headerData)
        
        // Seek to data fork
        try fileHandle.seek(toOffset: header.dataForkOffset)
        
        // Read data fork
        guard let dataForkData = try fileHandle.read(upToCount: Int(header.dataForkSize)) else {
            throw DC42Error.readFailed
        }
        
        return dataForkData
    }
    
    /// Read resource fork from DC42 image
    public func readResourceFork(url: URL) throws -> Data {
        let fileHandle = try FileHandle(forReadingFrom: url)
        defer { try? fileHandle.close() }
        
        // Read header
        guard let headerData = try fileHandle.read(upToCount: DC42Header.headerSize) else {
            throw DC42Error.invalidHeader
        }
        
        let header = try parseHeader(headerData)
        
        // If no resource fork, return empty
        guard header.resourceForkOffset > 0, header.resourceForkSize > 0 else {
            return Data()
        }
        
        // Seek to resource fork
        try fileHandle.seek(toOffset: header.resourceForkOffset)
        
        // Read resource fork
        guard let resourceForkData = try fileHandle.read(upToCount: Int(header.resourceForkSize)) else {
            throw DC42Error.readFailed
        }
        
        return resourceForkData
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
        
        // Set volume name
        var volumeNameBytes = [UInt8](volumeName.data(using: .macOSRoman) ?? Data())
        volumeNameBytes.append(contentsOf: [UInt8](repeating: 0, count: 64 - volumeNameBytes.count))
        header.volumeName = String(data: Data(volumeNameBytes.prefix(64)), encoding: .macOSRoman) ?? ""
        
        // Set sizes
        header.dataForkSize = UInt64(dataFork.count)
        header.resourceForkSize = UInt64(resourceFork?.count ?? 0)
        header.imageSize = UInt64(dataFork.count + (resourceFork?.count ?? 0))
        header.mediaSize = calculateMediaSize(for: UInt64(dataFork.count + (resourceFork?.count ?? 0)))
        
        // Set dates
        let now = Date()
        header.creationDate = dateToMacDate(now)
        header.modificationDate = dateToMacDate(now)
        
        // Set comment
        if let comment = comment {
            var commentBytes = [UInt8](comment.data(using: .macOSRoman) ?? Data())
            commentBytes.append(contentsOf: [UInt8](repeating: 0, count: 128 - commentBytes.count))
            header.comment = String(data: Data(commentBytes.prefix(128)), encoding: .macOSRoman) ?? ""
        }
        
        // Calculate checksum
        header.checksum = calculateChecksum(data: dataFork)
        
        // Write file
        let fileHandle = try FileHandle(forWritingTo: outputURL)
        defer { try? fileHandle.close() }
        
        // Write header
        let headerData = serializeHeader(header)
        try fileHandle.write(contentsOf: headerData)
        
        // Write data fork
        try fileHandle.write(contentsOf: dataFork)
        
        // Write resource fork
        if let resourceFork = resourceFork, resourceFork.count > 0 {
            try fileHandle.write(contentsOf: resourceFork)
        }
    }
    
    // MARK: - Conversion
    
    /// Convert DC42 to another format
    public func convert(
        sourceURL: URL,
        to format: ConversionFormat,
        progress: ((Double) -> Void)? = nil
    ) throws -> URL {
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory
            .appendingPathComponent("DC42Studio", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        progress?(0.1)
        
        switch format {
        case .dc42:
            // Already DC42, just copy
            let destURL = tempDir.appendingPathComponent(sourceURL.lastPathComponent)
            try fileManager.copyItem(at: sourceURL, to: destURL)
            progress?(1.0)
            return destURL
            
        case .iso:
            // Convert to ISO (HFS, not UDF - simplified)
            let isoData = try convertToISO(sourceURL: sourceURL)
            progress?(0.7)
            let destURL = tempDir
                .appendingPathComponent(sourceURL.deletingPathExtension().lastPathComponent)
                .appendingPathExtension("iso")
            try isoData.write(to: destURL)
            progress?(1.0)
            return destURL
            
        case .dmg:
            // Convert to DMG (simplified)
            let dmgData = try convertToDMG(sourceURL: sourceURL)
            progress?(0.7)
            let destURL = tempDir
                .appendingPathComponent(sourceURL.deletingPathExtension().lastPathComponent)
                .appendingPathExtension("dmg")
            try dmgData.write(to: destURL)
            progress?(1.0)
            return destURL
            
        case .folder:
            // Extract contents to folder
            try extractToFolder(sourceURL: sourceURL, destination: tempDir, progress: progress)
            return tempDir
            
        case .img:
            // Extract as raw IMG
            let data = try readDataFork(url: sourceURL)
            progress?(0.7)
            let destURL = tempDir
                .appendingPathComponent(sourceURL.deletingPathExtension().lastPathComponent)
                .appendingPathExtension("img")
            try data.write(to: destURL)
            progress?(1.0)
            return destURL
        }
    }
    
    /// Create DC42 from folder (simplified HFS filesystem)
    public func createFromFolder(
        sourceURL: URL,
        volumeName: String,
        progress: ((Double) -> Void)? = nil
    ) throws -> URL {
        let fileManager = FileManager.default
        
        // Read folder contents
        let contents = try fileManager.contentsOfDirectory(
            at: sourceURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )
        
        // Create a simple filesystem data (simplified implementation)
        var totalData = Data()
        var fileList: [(name: String, size: UInt64, offset: UInt64)] = []
        var currentOffset: UInt64 = 0
        
        progress?(0.1)
        
        for (index, file) in contents.enumerated() {
            let fileData = try Data(contentsOf: file)
            let fileSize = UInt64(fileData.count)
            
            fileList.append((name: file.lastPathComponent, size: fileSize, offset: currentOffset))
            totalData.append(fileData)
            
            // Align to 512 bytes
            let padding = (512 - (totalData.count % 512)) % 512
            if padding > 0 {
                totalData.append(contentsOf: [UInt8](repeating: 0, count: padding))
            }
            
            currentOffset = UInt64(totalData.count)
            
            progress?(Double(index + 1) / Double(contents.count) * 0.8)
        }
        
        // Create DC42
        let outputURL = fileManager.temporaryDirectory
            .appendingPathComponent("DC42Studio", isDirectory: true)
            .appendingPathComponent(UUID().uuidString + ".dc42")
        
        try fileManager.createDirectory(
            at: fileManager.temporaryDirectory.appendingPathComponent("DC42Studio", isDirectory: true),
            withIntermediateDirectories: true
        )
        
        try create(
            volumeName: volumeName,
            dataFork: totalData,
            to: outputURL
        )
        
        progress?(1.0)
        return outputURL
    }
    
    // MARK: - Private Helpers
    
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
    
    private func serializeHeader(_ header: DC42Header) -> Data {
        var data = Data(capacity: DC42Header.headerSize)
        
        // Magic
        data.append(contentsOf: header.magic)
        
        // Version
        data.append(UInt8(header.version & 0xFF))
        data.append(UInt8((header.version >> 8) & 0xFF))
        
        // Volume name (64 bytes)
        var volumeNameBytes = [UInt8](header.volumeName.data(using: .macOSRoman) ?? Data())
        volumeNameBytes.append(contentsOf: [UInt8](repeating: 0, count: 64 - volumeNameBytes.count))
        data.append(contentsOf: volumeNameBytes.prefix(64))
        
        // Image size
        data.append(contentsOf: writeUInt64(header.imageSize))
        
        // Media size
        data.append(contentsOf: writeUInt64(header.mediaSize))
        
        // Format flags
        data.append(UInt8(header.formatFlags & 0xFF))
        data.append(UInt8((header.formatFlags >> 8) & 0xFF))
        data.append(UInt8((header.formatFlags >> 16) & 0xFF))
        data.append(UInt8((header.formatFlags >> 24) & 0xFF))
        
        // Checksum
        data.append(UInt8(header.checksum & 0xFF))
        data.append(UInt8((header.checksum >> 8) & 0xFF))
        data.append(UInt8((header.checksum >> 16) & 0xFF))
        data.append(UInt8((header.checksum >> 24) & 0xFF))
        
        // Comment (128 bytes)
        var commentBytes = [UInt8](header.comment.data(using: .macOSRoman) ?? Data())
        commentBytes.append(contentsOf: [UInt8](repeating: 0, count: 128 - commentBytes.count))
        data.append(contentsOf: commentBytes.prefix(128))
        
        // Data fork offset
        data.append(contentsOf: writeUInt64(header.dataForkOffset))
        
        // Resource fork offset
        data.append(contentsOf: writeUInt64(header.resourceForkOffset))
        
        // Data fork size
        data.append(contentsOf: writeUInt64(header.dataForkSize))
        
        // Resource fork size
        data.append(contentsOf: writeUInt64(header.resourceForkSize))
        
        // Creation date
        data.append(UInt8(header.creationDate & 0xFF))
        data.append(UInt8((header.creationDate >> 8) & 0xFF))
        data.append(UInt8((header.creationDate >> 16) & 0xFF))
        data.append(UInt8((header.creationDate >> 24) & 0xFF))
        
        // Modification date
        data.append(UInt8(header.modificationDate & 0xFF))
        data.append(UInt8((header.modificationDate >> 8) & 0xFF))
        data.append(UInt8((header.modificationDate >> 16) & 0xFF))
        data.append(UInt8((header.modificationDate >> 24) & 0xFF))
        
        // Reserved (250 bytes to reach 512 total)
        data.append(contentsOf: [UInt8](repeating: 0, count: DC42Header.headerSize - data.count))
        
        return data
    }
    
    private func macDateToDate(_ macDate: UInt32) -> Date? {
        // Mac date is seconds since Jan 1, 1904
        let secondsSince1904 = Double(macDate)
        let secondsSince1970 = secondsSince1904 - 2082844800 // Offset from 1904 to 1970
        return Date(timeIntervalSince1970: secondsSince1970)
    }
    
    private func dateToMacDate(_ date: Date) -> UInt32 {
        let secondsSince1970 = date.timeIntervalSince1970
        let secondsSince1904 = secondsSince1970 + 2082844800
        return UInt32(max(0, secondsSince1904))
    }
    
    private func calculateChecksum(data: Data) -> UInt32 {
        // Simple checksum calculation
        let bytes = [UInt8](data)
        var sum: UInt32 = 0
        for byte in bytes {
            sum = sum &+ UInt32(byte)
        }
        return sum
    }
    
    private func calculateMediaSize(for dataSize: UInt64) -> UInt64 {
        let blockSize: UInt64 = 512
        let blocks = (dataSize + blockSize - 1) / blockSize
        return blocks * blockSize
    }
    
    private func determineDiskFormat(imageSize: UInt64) -> DC42DiskFormat {
        switch imageSize {
        case 0..<500_000: return .floppy400KB
        case 500_000..<1_000_000: return .floppy800KB
        case 1_000_000..<1_600_000: return .floppy1440KB
        case 1_600_000..<3_000_000: return .floppy2880KB
        default: return .hardDisk
        }
    }
    
    private func convertToISO(sourceURL: URL) throws -> Data {
        // Simplified HFS to ISO conversion
        let dataFork = try readDataFork(url: sourceURL)
        return dataFork
    }
    
    private func convertToDMG(sourceURL: URL) throws -> Data {
        // Simplified DMG creation
        let dataFork = try readDataFork(url: sourceURL)
        return dataFork
    }
    
    private func extractToFolder(
        sourceURL: URL,
        destination: URL,
        progress: ((Double) -> Void)?
    ) throws {
        let dataFork = try readDataFork(url: sourceURL)
        // In a full implementation, we would parse HFS filesystem here
        // For now, save as raw data
        let outputFile = destination.appendingPathComponent("contents.dat")
        try dataFork.write(to: outputFile)
        progress?(1.0)
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
    
    public var errorDescription: String? {
        switch self {
        case .invalidHeader: return "Invalid DC42 header"
        case .invalidMagic: return "Not a valid DC42 file (missing CD42 magic)"
        case .invalidFormat: return "Invalid DC42 format"
        case .readFailed: return "Failed to read DC42 file"
        case .writeFailed: return "Failed to write DC42 file"
        case .checksumMismatch: return "Checksum mismatch - file may be corrupted"
        case .unsupportedVersion: return "Unsupported DC42 version"
        }
    }
}
