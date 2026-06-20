import Foundation
import UniformTypeIdentifiers

/// DC42 Image Format Types
public enum DC42FormatType: UInt16, Codable, CaseIterable {
    case standard = 2
    case withComment = 4
    case compressed = 8
    
    var description: String {
        switch self {
        case .standard: return "Standard DC42"
        case .withComment: return "DC42 with Comment"
        case .compressed: return "Compressed DC42"
        }
    }
}

/// DC42 Disk Format Types
public enum DC42DiskFormat: UInt16, Codable {
    case unknown = 0
    case fixed = 1
    case floppy400KB = 2
    case floppy800KB = 3
    case floppy1440KB = 4
    case floppy2880KB = 5
    case hardDisk = 6
    
    var description: String {
        switch self {
        case .unknown: return "Unknown"
        case .fixed: return "Fixed Disk"
        case .floppy400KB: return "400 KB Floppy"
        case .floppy800KB: return "800 KB Floppy"
        case .floppy1440KB: return "1.44 MB Floppy"
        case .floppy2880KB: return "2.88 MB Floppy"
        case .hardDisk: return "Hard Disk"
        }
    }
    
    var sectorSize: Int {
        switch self {
        case .floppy400KB, .floppy800KB: return 512
        case .floppy1440KB, .floppy2880KB: return 512
        case .hardDisk, .fixed: return 512
        case .unknown: return 512
        }
    }
}

/// DC42 Image File Handle
public struct DC42Image: Identifiable, Codable, Hashable {
    public let id: UUID
    public var fileURL: URL
    public var volumeName: String
    public var totalSize: UInt64
    public var usedSize: UInt64
    public var formatType: DC42FormatType
    public var diskFormat: DC42DiskFormat
    public var dataForkSize: UInt64
    public var resourceForkSize: UInt64
    public var creationDate: Date?
    public var modificationDate: Date?
    public var comment: String?
    public var isValid: Bool
    public var fileCount: Int
    
    public init(
        id: UUID = UUID(),
        fileURL: URL,
        volumeName: String = "Untitled",
        totalSize: UInt64 = 0,
        usedSize: UInt64 = 0,
        formatType: DC42FormatType = .standard,
        diskFormat: DC42DiskFormat = .unknown,
        dataForkSize: UInt64 = 0,
        resourceForkSize: UInt64 = 0,
        creationDate: Date? = nil,
        modificationDate: Date? = nil,
        comment: String? = nil,
        isValid: Bool = false,
        fileCount: Int = 0
    ) {
        self.id = id
        self.fileURL = fileURL
        self.volumeName = volumeName
        self.totalSize = totalSize
        self.usedSize = usedSize
        self.formatType = formatType
        self.diskFormat = diskFormat
        self.dataForkSize = dataForkSize
        self.resourceForkSize = resourceForkSize
        self.creationDate = creationDate
        self.modificationDate = modificationDate
        self.comment = comment
        self.isValid = isValid
        self.fileCount = fileCount
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    public static func == (lhs: DC42Image, rhs: DC42Image) -> Bool {
        lhs.id == rhs.id
    }
}

/// DC42 Header Structure (512 bytes)
public struct DC42Header {
    public static let magicNumber: [UInt8] = [0x43, 0x44, 0x34, 0x32] // "CD42"
    public static let headerSize: Int = 512
    
    public var magic: [UInt8]              // 0-3: "CD42"
    public var version: UInt16              // 4-5: Version number
    public var volumeName: String           // 6-69: Volume name (64 bytes)
    public var imageSize: UInt64            // 70-77: Image data size
    public var mediaSize: UInt64            // 78-85: Media size
    public var formatFlags: UInt32          // 86-89: Format flags
    public var checksum: UInt32             // 90-93: Checksum
    public var comment: String              // 94-221: Comment (128 bytes)
    public var dataForkOffset: UInt64       // 222-229: Data fork offset
    public var resourceForkOffset: UInt64   // 230-237: Resource fork offset
    public var dataForkSize: UInt64         // 238-245: Data fork size
    public var resourceForkSize: UInt64     // 246-253: Resource fork size
    public var creationDate: UInt32         // 254-257: Creation date (Mac format)
    public var modificationDate: UInt32      // 258-261: Modification date (Mac format)
    public var reserved: [UInt8]            // 262-511: Reserved
    
    public init() {
        self.magic = DC42Header.magicNumber
        self.version = 2
        self.volumeName = String(repeating: "\0", count: 64)
        self.imageSize = 0
        self.mediaSize = 0
        self.formatFlags = 0
        self.checksum = 0
        self.comment = String(repeating: "\0", count: 128)
        self.dataForkOffset = UInt64(DC42Header.headerSize)
        self.resourceForkOffset = 0
        self.dataForkSize = 0
        self.resourceForkSize = 0
        self.creationDate = 0
        self.modificationDate = 0
        self.reserved = [UInt8](repeating: 0, count: 250)
    }
}

/// Conversion Output Format
public enum ConversionFormat: String, CaseIterable, Identifiable {
    case dc42 = "DC42"
    case iso = "ISO"
    case dmg = "DMG"
    case folder = "Folder"
    case img = "IMG"
    
    public var id: String { rawValue }
    
    public var fileExtension: String {
        switch self {
        case .dc42: return "dc42"
        case .iso: return "iso"
        case .dmg: return "dmg"
        case .folder: return "directory"
        case .img: return "img"
        }
    }
    
    public var utType: UTType {
        switch self {
        case .dc42: return UTType(filenameExtension: "dc42") ?? .data
        case .iso: return .iso
        case .dmg: return .diskImage
        case .folder: return .folder
        case .img: return UTType(filenameExtension: "img") ?? .data
        }
    }
    
    public var description: String {
        switch self {
        case .dc42: return "DiskCopy 4.2 Image"
        case .iso: return "ISO 9660 Image"
        case .dmg: return "Apple DMG Image"
        case .folder: return "Folder"
        case .img: return "Raw Disk Image"
        }
    }
    
    public var icon: String {
        switch self {
        case .dc42: return "internaldrive"
        case .iso: return "opticaldisc"
        case .dmg: return "externaldrive"
        case .folder: return "folder"
        case .img: return "doc"
        }
    }
}

/// Conversion Job Status
public enum ConversionJobStatus: Equatable {
    case pending
    case inProgress(Double)
    case completed
    case failed(String)
    
    public var isCompleted: Bool {
        switch self {
        case .completed: return true
        default: return false
        }
    }
    
    public var isFailed: Bool {
        switch self {
        case .failed: return true
        default: return false
        }
    }
}

/// Conversion Job
public struct ConversionJob: Identifiable {
    public let id: UUID
    public var sourceFile: URL
    public var outputFormat: ConversionFormat
    public var outputURL: URL?
    public var status: ConversionJobStatus
    public var startTime: Date?
    public var endTime: Date?
    public var errorMessage: String?
    
    public init(
        id: UUID = UUID(),
        sourceFile: URL,
        outputFormat: ConversionFormat,
        outputURL: URL? = nil,
        status: ConversionJobStatus = .pending
    ) {
        self.id = id
        self.sourceFile = sourceFile
        self.outputFormat = outputFormat
        self.outputURL = outputURL
        self.status = status
        self.startTime = Date()
        self.endTime = nil
        self.errorMessage = nil
    }
}
