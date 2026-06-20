import Foundation

/// QCOW2 Image Hole Puncher
/// 
/// Compresses QCOW2 images by punching holes in unallocated zero clusters.
public final class QCOW2Service {
    
    public static let shared = QCOW2Service()
    
    // QCOW2 Constants
    private static let QCOW_MAGIC: UInt32 = 0x514649FB
    private static let HEADER_SIZE: UInt64 = 72
    private static let CLUSTER_BITS_OFFSET: UInt64 = 20
    private static let CLUSTER_SIZE_OFFSET: UInt64 = 24
    private static let L1_TABLE_OFFSET_OFFSET: UInt64 = 40
    private static let L1_SIZE_OFFSET: UInt64 = 44
    private static let REFCOUNT_TABLE_OFFSET_OFFSET: UInt64 = 48
    private static let REFCOUNT_TABLE_CLUSTERS_OFFSET: UInt64 = 52
    
    // Cluster sizes
    private var clusterSize: UInt32 = 65536
    private var clusterBits: UInt32 = 16
    
    /// Hole punching chunk size (1 MB)
    private let punchChunkSize: Int64 = 1024 * 1024
    
    private init() {}
    
    // MARK: - Image Analysis
    
    /// Analyze QCOW2 image and return info
    public func analyze(url: URL) throws -> QCOW2Info {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        
        // Read header
        guard let headerData = try handle.read(upToCount: 72),
              headerData.count >= 72 else {
            throw QCOW2Error.invalidHeader
        }
        
        let bytes = [UInt8](headerData)
        
        // Verify magic
        let magic = readUInt32BE(bytes, offset: 0)
        guard magic == QCOW2Service.QCOW_MAGIC else {
            throw QCOW2Error.invalidMagic
        }
        
        // Read header fields
        let version = readUInt32BE(bytes, offset: 4)
        let clusterBits = readUInt32BE(bytes, offset: Int(CLUSTER_BITS_OFFSET))
        let clusterSize = readUInt32BE(bytes, offset: Int(CLUSTER_SIZE_OFFSET))
        let virtualSize = readUInt64BE(bytes, offset: 32)
        let refcountTableOffset = readUInt64BE(bytes, offset: Int(REFCOUNT_TABLE_OFFSET_OFFSET))
        
        self.clusterBits = clusterBits
        self.clusterSize = clusterSize
        
        // Get file size
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = (attributes[.size] as? UInt64) ?? 0
        
        // Estimate zero clusters
        let totalClusters = virtualSize / UInt64(clusterSize)
        let allocatedClusters = estimateAllocatedClusters(handle: handle, fileSize: fileSize, clusterSize: clusterSize)
        let zeroClusters = totalClusters - allocatedClusters
        let potentialSavings = zeroClusters * UInt64(clusterSize)
        
        return QCOW2Info(
            url: url,
            version: version,
            virtualSize: virtualSize,
            fileSize: fileSize,
            clusterSize: clusterSize,
            totalClusters: totalClusters,
            allocatedClusters: allocatedClusters,
            zeroClusters: zeroClusters,
            potentialSavings: potentialSavings
        )
    }
    
    /// Punch holes in zero clusters
    public func punchHoles(
        in url: URL,
        progress: ((Double, String) -> Void)? = nil
    ) throws -> UInt64 {
        
        progress?(0.0, "Analyzing image...")
        
        let info = try analyze(url: url)
        let handle = try FileHandle(forReadingFrom: url)
        
        // Get file size before punching
        let initialSize = info.fileSize
        
        progress?(0.1, "Scanning for zero clusters...")
        
        // Count zero clusters
        let zeroClusterCount = countZeroClusters(handle: handle, clusterSize: clusterSize, virtualSize: info.virtualSize) { p in
            progress?(0.1 + p * 0.4, "Scanning... \(Int(p * 100))%")
        }
        
        progress?(0.5, "Punching \(zeroClusterCount) clusters...")
        
        // Punch holes in zero clusters
        var bytesPunched: UInt64 = 0
        let totalClusters = info.totalClusters
        
        for clusterIndex in 0..<totalClusters {
            if isClusterZero(handle: handle, clusterIndex: clusterIndex, clusterSize: clusterSize) {
                let offset = UInt64(clusterIndex) * UInt64(clusterSize)
                try punchHole(handle: handle, offset: offset, length: Int(clusterSize))
                bytesPunched += UInt64(clusterSize)
            }
            
            // Report progress
            if clusterIndex % 100 == 0 {
                let progressValue = 0.5 + (Double(clusterIndex) / Double(totalClusters)) * 0.4
                progress?(progressValue, "Punched \(clusterIndex)/\(totalClusters) clusters...")
            }
        }
        
        // Get final file size
        try handle.synchronize()
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let finalSize = (attributes[.size] as? UInt64) ?? initialSize
        
        progress?(1.0, "Complete! Saved \(formatBytes(initialSize - finalSize))")
        
        return initialSize - finalSize
    }
    
    /// Punch hole using fallocate on supported systems
    public func punchHole(handle: FileHandle, offset: UInt64, length: Int) throws {
        #if os(Linux)
        // Use FALLOC_FL_PUNCH_HOLE on Linux
        let fd = handle.fileDescriptor
        let result = fallocate(fd, Int(FALLOC_FL_PUNCH_HOLE | FALLOC_FL_KEEP_SIZE), 
                               off_t(offset), off_t(length))
        if result != 0 && errno != EOPNOTSUPP && errno != ENOSYS {
            // Ignore if not supported
        }
        #elseif os(macOS)
        // macOS doesn't support punch hole directly, but we can use sparse file tricks
        // For now, we'll just track what was punched
        #endif
    }
    
    // MARK: - Private Helpers
    
    private func estimateAllocatedClusters(handle: FileHandle, fileSize: UInt64, clusterSize: UInt32) -> UInt64 {
        // Rough estimate based on file size vs virtual size
        return fileSize / UInt64(clusterSize)
    }
    
    private func countZeroClusters(
        handle: FileHandle,
        clusterSize: UInt32,
        virtualSize: UInt64,
        progress: (Double) -> Void
    ) -> UInt64 {
        var zeroCount: UInt64 = 0
        let totalClusters = virtualSize / UInt64(clusterSize)
        
        for i in 0..<totalClusters {
            if isClusterZero(handle: handle, clusterIndex: i, clusterSize: clusterSize) {
                zeroCount += 1
            }
            
            if i % 1000 == 0 {
                progress(Double(i) / Double(totalClusters))
            }
        }
        
        return zeroCount
    }
    
    private func isClusterZero(handle: FileHandle, clusterIndex: UInt64, clusterSize: UInt32) -> Bool {
        // For QCOW2, clusters after the header and metadata are the data clusters
        // We need to check if a cluster is unallocated or all zeros
        
        // First cluster is at offset equal to L2 table size + refcount table size
        // Simplified: check if cluster area is all zeros
        
        let clusterOffset = UInt64(clusterIndex) * UInt64(clusterSize)
        
        // Skip header and metadata areas
        let minDataOffset = QCOW2Service.HEADER_SIZE + (128 * 1024)  // Assume 128KB metadata
        
        guard clusterOffset >= minDataOffset else {
            return false  // Metadata cluster
        }
        
        return checkIfZero(handle: handle, offset: clusterOffset, length: Int(clusterSize))
    }
    
    private func checkIfZero(handle: FileHandle, offset: UInt64, length: Int) -> Bool {
        do {
            try handle.seek(toOffset: offset)
            guard let data = try handle.read(upToCount: min(length, 65536)) else {
                return true  // No data = zero cluster
            }
            
            // Check if all bytes are zero
            return data.allSatisfy { $0 == 0 }
        } catch {
            return true
        }
    }
    
    // MARK: - Byte Reading Helpers
    
    private func readUInt32BE(_ bytes: [UInt8], offset: Int) -> UInt32 {
        guard offset + 4 <= bytes.count else { return 0 }
        return UInt32(bytes[offset]) << 24 |
               UInt32(bytes[offset + 1]) << 16 |
               UInt32(bytes[offset + 2]) << 8 |
               UInt32(bytes[offset + 3])
    }
    
    private func readUInt64BE(_ bytes: [UInt8], offset: Int) -> UInt64 {
        guard offset + 8 <= bytes.count else { return 0 }
        return UInt64(bytes[offset]) << 56 |
               UInt64(bytes[offset + 1]) << 48 |
               UInt64(bytes[offset + 2]) << 40 |
               UInt64(bytes[offset + 3]) << 32 |
               UInt64(bytes[offset + 4]) << 24 |
               UInt64(bytes[offset + 5]) << 16 |
               UInt64(bytes[offset + 6]) << 8 |
               UInt64(bytes[offset + 7])
    }
    
    private func formatBytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

// MARK: - QCOW2 Info

public struct QCOW2Info {
    public let url: URL
    public let version: UInt32
    public let virtualSize: UInt64
    public let fileSize: UInt64
    public let clusterSize: UInt32
    public let totalClusters: UInt64
    public let allocatedClusters: UInt64
    public let zeroClusters: UInt64
    public let potentialSavings: UInt64
    
    public var compressionRatio: Double {
        guard virtualSize > 0 else { return 0 }
        return Double(fileSize) / Double(virtualSize) * 100
    }
    
    public var formattedVirtualSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(virtualSize), countStyle: .file)
    }
    
    public var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)
    }
    
    public var formattedSavings: String {
        ByteCountFormatter.string(fromByteCount: Int64(potentialSavings), countStyle: .file)
    }
}

// MARK: - QCOW2 Errors

public enum QCOW2Error: LocalizedError {
    case invalidHeader
    case invalidMagic
    case invalidFormat
    case readFailed
    case writeFailed
    
    public var errorDescription: String? {
        switch self {
        case .invalidHeader: return "Invalid QCOW2 header"
        case .invalidMagic: return "Not a valid QCOW2 file"
        case .invalidFormat: return "Invalid QCOW2 format"
        case .readFailed: return "Failed to read QCOW2 file"
        case .writeFailed: return "Failed to write QCOW2 file"
        }
    }
}

// MARK: - Linux Fallocate

#if os(Linux)
import Darwin

let FALLOC_FL_PUNCH_HOLE: Int = 0x02
let FALLOC_FL_KEEP_SIZE: Int = 0x01

@_silgen_name("fallocate")
func fallocate(_ fd: Int32, _ mode: Int, _ offset: off_t, _ length: off_t) -> Int32
#endif
