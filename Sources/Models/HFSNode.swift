import Foundation

/// HFS File/Folder Node
public struct HFSNode: Identifiable, Hashable {
    public let id: UUID
    public var name: String
    public var isDirectory: Bool
    public var size: UInt64
    public var creationDate: Date?
    public var modificationDate: Date?
    public var typeCode: String
    public var creatorCode: String
    public var permissions: HFSNodePermissions
    public var children: [HFSNode]?
    public var path: String
    
    public init(
        id: UUID = UUID(),
        name: String,
        isDirectory: Bool,
        size: UInt64 = 0,
        creationDate: Date? = nil,
        modificationDate: Date? = nil,
        typeCode: String = "????",
        creatorCode: String = "????",
        permissions: HFSNodePermissions = .default,
        children: [HFSNode]? = nil,
        path: String = ""
    ) {
        self.id = id
        self.name = name
        self.isDirectory = isDirectory
        self.size = size
        self.creationDate = creationDate
        self.modificationDate = modificationDate
        self.typeCode = typeCode
        self.creatorCode = creatorCode
        self.permissions = permissions
        self.children = children
        self.path = path
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    public static func == (lhs: HFSNode, rhs: HFSNode) -> Bool {
        lhs.id == rhs.id
    }
    
    /// Get appropriate SF Symbol icon name
    public var iconName: String {
        if isDirectory {
            return "folder.fill"
        }
        
        // Use type code to determine icon
        switch typeCode {
        case "APPL": return "app.fill"
        case "CODE": return "doc.text.fill"
        case "TEXT": return "doc.fill"
        case "TIFF": return "photo.fill"
        case "PNTG": return "paintpalette.fill"
        case "MooV": return "film.fill"
        case "snd ": return "speaker.wave.2.fill"
        case "ZIP ", "SIT ": return "archivebox.fill"
        case "PDF ": return "doc.richtext.fill"
        default: return "doc.fill"
        }
    }
}

/// HFS Node Permissions
public struct HFSNodePermissions: OptionSet, Codable {
    public let rawValue: UInt16
    
    public init(rawValue: UInt16) {
        self.rawValue = rawValue
    }
    
    public static let readable       = HFSNodePermissions(rawValue: 1 << 0)
    public static let writable       = HFSNodePermissions(rawValue: 1 << 1)
    public static let locked         = HFSNodePermissions(rawValue: 1 << 2)
    public static let invisible      = HFSNodePermissions(rawValue: 1 << 3)
    public static let bundle         = HFSNodePermissions(rawValue: 1 << 4)
    public static let system         = HFSNodePermissions(rawValue: 1 << 5)
    public static let booted         = HFSNodePermissions(rawValue: 1 << 6)
    public static let inited         = HFSNodePermissions(rawValue: 1 << 7)
    public static let changed        = HFSNodePermissions(rawValue: 1 << 8)
    
    public static let `default`: HFSNodePermissions = [.readable, .writable, .inited]
}

/// HFS Volume Information
public struct HFSVolumeInfo {
    public var volumeName: String
    public var volumeCreationDate: Date?
    public var volumeModificationDate: Date?
    public var totalBlocks: UInt32
    public var freeBlocks: UInt32
    public var blockSize: UInt32
    public var filesCount: Int
    public var foldersCount: Int
    
    public var totalSize: UInt64 {
        UInt64(totalBlocks) * UInt64(blockSize)
    }
    
    public var freeSize: UInt64 {
        UInt64(freeBlocks) * UInt64(blockSize)
    }
    
    public var usedSize: UInt64 {
        totalSize - freeSize
    }
    
    public init(
        volumeName: String = "Untitled",
        volumeCreationDate: Date? = nil,
        volumeModificationDate: Date? = nil,
        totalBlocks: UInt32 = 0,
        freeBlocks: UInt32 = 0,
        blockSize: UInt32 = 512,
        filesCount: Int = 0,
        foldersCount: Int = 0
    ) {
        self.volumeName = volumeName
        self.volumeCreationDate = volumeCreationDate
        self.volumeModificationDate = volumeModificationDate
        self.totalBlocks = totalBlocks
        self.freeBlocks = freeBlocks
        self.blockSize = blockSize
        self.filesCount = filesCount
        self.foldersCount = foldersCount
    }
}

/// File Extraction Item
public struct ExtractionItem: Identifiable {
    public let id: UUID
    public var node: HFSNode
    public var extractedSize: UInt64 = 0
    public var status: ExtractionStatus
    
    public init(
        id: UUID = UUID(),
        node: HFSNode,
        extractedSize: UInt64 = 0,
        status: ExtractionStatus = .pending
    ) {
        self.id = id
        self.node = node
        self.extractedSize = extractedSize
        self.status = status
    }
}

/// Extraction Status
public enum ExtractionStatus: Equatable {
    case pending
    case inProgress(Double)
    case completed
    case failed(String)
    case skipped
}
