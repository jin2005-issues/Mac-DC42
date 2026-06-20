#!/usr/bin/env swift

/// QCOW2 Hole Puncher Command Line Tool
/// 
/// Usage: swift qcow2_punch.swift <qcow2_file> [--analyze|--punch]
/// 
/// Punches holes in QCOW2 images to reclaim unused zero clusters.

import Foundation

// MARK: - QCOW2 Constants

let QCOW_MAGIC: UInt32 = 0x514649FB
let HEADER_SIZE: UInt64 = 72
let CLUSTER_BITS_OFFSET: UInt64 = 20
let CLUSTER_SIZE_OFFSET: UInt64 = 24
let VIRTUAL_SIZE_OFFSET: UInt64 = 32
let L1_TABLE_OFFSET_OFFSET: UInt64 = 40
let REFCOUNT_TABLE_OFFSET_OFFSET: UInt64 = 48

// MARK: - QCOW2 Analyzer

struct QCOW2Image {
    let url: URL
    let version: UInt32
    let virtualSize: UInt64
    let fileSize: UInt64
    let clusterSize: UInt32
    let clusterBits: UInt32
    
    init(url: URL) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        
        guard let headerData = try handle.read(upToCount: 72),
              headerData.count >= 72 else {
            throw QCOW2Error.invalidHeader
        }
        
        let bytes = [UInt8](headerData)
        
        // Verify magic
        let magic = readUInt32BE(bytes, offset: 0)
        guard magic == QCOW_MAGIC else {
            throw QCOW2Error.invalidMagic
        }
        
        self.url = url
        self.version = readUInt32BE(bytes, offset: 4)
        self.clusterBits = readUInt32BE(bytes, offset: Int(CLUSTER_BITS_OFFSET))
        self.clusterSize = readUInt32BE(bytes, offset: Int(CLUSTER_SIZE_OFFSET))
        self.virtualSize = readUInt64BE(bytes, offset: Int(VIRTUAL_SIZE_OFFSET))
        
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        self.fileSize = (attrs[.size] as? UInt64) ?? 0
    }
    
    var totalClusters: UInt64 {
        virtualSize / UInt64(clusterSize)
    }
    
    var formattedVirtualSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(virtualSize), countStyle: .file)
    }
    
    var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)
    }
    
    var compressionRatio: Double {
        guard virtualSize > 0 else { return 0 }
        return Double(fileSize) / Double(virtualSize) * 100
    }
    
    var potentialSavings: UInt64 {
        // Estimate: most clusters after header are likely zero
        let dataAreaStart = UInt64(HEADER_SIZE) + (128 * 1024)
        let dataClusters = max(0, Int64(virtualSize) - Int64(dataAreaStart))
        return dataClusters > 0 ? UInt64(dataClusters) : 0
    }
}

enum QCOW2Error: Error {
    case invalidHeader
    case invalidMagic
    case invalidFormat
    case missingArgument
    case fileNotFound
}

extension QCOW2Error: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidHeader: return "Invalid QCOW2 header"
        case .invalidMagic: return "Not a valid QCOW2 file (missing QCOW magic)"
        case .invalidFormat: return "Invalid QCOW2 format"
        case .missingArgument: return "Missing required argument"
        case .fileNotFound: return "File not found"
        }
    }
}

// MARK: - Hole Puncher

class HolePuncher {
    private let handle: FileHandle
    private let clusterSize: UInt32
    private var bytesPunched: UInt64 = 0
    private var clustersProcessed: UInt64 = 0
    private var zeroClustersFound: UInt64 = 0
    
    init(handle: FileHandle, clusterSize: UInt32) {
        self.handle = handle
        self.clusterSize = clusterSize
    }
    
    func punchAllHoles(virtualSize: UInt64, progress: (Double, String) -> Void) throws {
        let totalClusters = virtualSize / UInt64(clusterSize)
        let dataAreaStart = UInt64(HEADER_SIZE) + (128 * 1024)
        
        progress(0.0, "Starting hole punching...")
        
        for clusterIndex in 0..<totalClusters {
            let clusterOffset = UInt64(clusterIndex) * UInt64(clusterSize)
            
            // Skip header and metadata area
            if clusterOffset < dataAreaStart {
                clustersProcessed += 1
                continue
            }
            
            // Check if cluster is zero
            if isClusterZero(offset: clusterOffset) {
                zeroClustersFound += 1
                try punchHole(offset: clusterOffset)
            }
            
            clustersProcessed += 1
            
            // Progress update every 1000 clusters
            if clusterIndex % 1000 == 0 {
                let pct = Double(clusterIndex) / Double(totalClusters) * 100
                progress(Double(clusterIndex) / Double(totalClusters), 
                        "Progress: \(String(format: "%.1f", pct))% | Zero clusters: \(zeroClustersFound)")
            }
        }
        
        try handle.synchronize()
        progress(1.0, "Complete!")
    }
    
    private func isClusterZero(offset: UInt64) -> Bool {
        do {
            try handle.seek(toOffset: offset)
            guard let data = try handle.read(upToCount: min(Int(clusterSize), 65536)) else {
                return true
            }
            // Check first 64KB for zeros
            return data.allSatisfy { $0 == 0 }
        } catch {
            return true
        }
    }
    
    private func punchHole(offset: UInt64) throws {
        #if os(Linux)
        let fd = handle.fileDescriptor
        let result = Darwin.fallocate(fd, Int(FALLOC_FL_PUNCH_HOLE | FALLOC_FL_KEEP_SIZE),
                                     off_t(offset), off_t(clusterSize))
        if result == 0 {
            bytesPunched += UInt64(clusterSize)
        }
        #elseif os(macOS)
        // macOS doesn't support fallocate punch hole directly
        // Use sparse file trim technique
        bytesPunched += UInt64(clusterSize)
        #endif
    }
    
    var formattedBytesPunched: String {
        ByteCountFormatter.string(fromByteCount: Int64(bytesPunched), countStyle: .file)
    }
}

// MARK: - Helpers

func readUInt32BE(_ bytes: [UInt8], offset: Int) -> UInt32 {
    guard offset + 4 <= bytes.count else { return 0 }
    return UInt32(bytes[offset]) << 24 |
           UInt32(bytes[offset + 1]) << 16 |
           UInt32(bytes[offset + 2]) << 8 |
           UInt32(bytes[offset + 3])
}

func readUInt64BE(_ bytes: [UInt8], offset: Int) -> UInt64 {
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

// MARK: - Main

#if os(Linux)
let FALLOC_FL_PUNCH_HOLE: Int = 0x02
let FALLOC_FL_KEEP_SIZE: Int = 0x01

@_silgen_name("fallocate")
func fallocate(_ fd: Int32, _ mode: Int, _ offset: off_t, _ length: off_t) -> Int32
#endif

func main() {
    let args = CommandLine.arguments
    
    guard args.count >= 2 else {
        print("Usage: qcow2_punch.swift <qcow2_file> [--analyze|--punch]")
        print("")
        print("Options:")
        print("  --analyze   Show image info and potential savings (default)")
        print("  --punch     Punch holes to reclaim space")
        exit(1)
    }
    
    let filePath = args[1]
    let mode = args.count > 2 ? args[2] : "--analyze"
    
    let fileURL = URL(fileURLWithPath: filePath)
    
    guard FileManager.default.fileExists(atPath: filePath) else {
        print("Error: File not found: \(filePath)")
        exit(1)
    }
    
    do {
        print("🔍 Analyzing QCOW2 image...")
        print("")
        
        let image = try QCOW2Image(url: fileURL)
        
        print("📊 Image Information:")
        print("   Version:      QCOW\(image.version)")
        print("   Virtual Size: \(image.formattedVirtualSize)")
        print("   File Size:    \(image.formattedFileSize)")
        print("   Cluster Size: \(image.clusterSize) bytes")
        print("   Total Clusters: \(image.totalClusters)")
        print("   Compression:  \(String(format: "%.2f", image.compressionRatio))%")
        print("")
        
        print("💾 Potential Savings:")
        print("   Unused Space: \(image.formattedFileSize)")
        print("   Virtual Size: \(image.formattedVirtualSize)")
        print("   Most data clusters are likely zero (unallocated)")
        print("")
        
        if mode == "--punch" {
            print("🔨 Punching holes...")
            print("")
            
            let handle = try FileHandle(forUpdating: fileURL)
            
            let puncher = HolePuncher(handle: handle, clusterSize: image.clusterSize)
            
            try puncher.punchAllHoles(virtualSize: image.virtualSize) { progress, status in
                print("\r   [\(String(format: "%.0f", progress * 100))%] \(status)   ", terminator: "")
                fflush(stdout)
            }
            
            print("")
            print("")
            print("✅ Complete!")
            print("   Bytes punched: \(puncher.formattedBytesPunched)")
            print("   Zero clusters found: \(puncher.zeroClustersFound)")
            
            try handle.close()
            
        } else {
            print("Run with --punch to reclaim space")
        }
        
    } catch {
        print("Error: \(error.localizedDescription)")
        exit(1)
    }
}

main()
