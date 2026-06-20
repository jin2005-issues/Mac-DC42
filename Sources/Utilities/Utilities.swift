import Foundation

// MARK: - Byte Formatter

/// Utility for formatting byte values
struct ByteFormatter {
    static func format(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
    
    static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

// MARK: - HFS Date Utilities

/// HFS Date Conversion Utilities
struct HFSDate {
    /// Convert Mac date (seconds since 1904) to Date
    static func toDate(_ macDate: UInt32) -> Date? {
        let secondsSince1904 = Double(macDate)
        let secondsSince1970 = secondsSince1904 - 2082844800 // Offset from 1904 to 1970
        return Date(timeIntervalSince1970: secondsSince1970)
    }
    
    /// Convert Date to Mac date
    static func fromDate(_ date: Date) -> UInt32 {
        let secondsSince1970 = date.timeIntervalSince1970
        let secondsSince1904 = secondsSince1970 + 2082844800
        return UInt32(max(0, secondsSince1904))
    }
}

// MARK: - Checksum Calculator

/// CRC32 Checksum Calculator
struct ChecksumCalculator {
    private static let table: [UInt32] = {
        var table = [UInt32](repeating: 0, count: 256)
        for i in 0..<256 {
            var crc = UInt32(i)
            for _ in 0..<8 {
                if crc & 1 == 1 {
                    crc = (crc >> 1) ^ 0xEDB88320
                } else {
                    crc >>= 1
                }
            }
            table[i] = crc
        }
        return table
    }()
    
    /// Calculate CRC32 checksum
    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = (crc >> 8) ^ table[index]
        }
        return crc ^ 0xFFFFFFFF
    }
    
    /// Simple checksum (sum of bytes)
    static func simple(_ data: Data) -> UInt32 {
        var sum: UInt32 = 0
        for byte in data {
            sum = sum &+ UInt32(byte)
        }
        return sum
    }
}

// MARK: - File Type Detection

/// Utility for detecting file types
struct FileTypeDetector {
    /// Detect if data is a DC42 file
    static func isDC42(_ data: Data) -> Bool {
        guard data.count >= 4 else { return false }
        return data[0] == 0x43 && data[1] == 0x44 && data[2] == 0x34 && data[3] == 0x32
    }
    
    /// Detect if data is an ISO file
    static func isISO(_ data: Data) -> Bool {
        guard data.count >= 32769 else { return false }
        // Check for ISO 9660 primary volume descriptor
        let slice = data[32769..<32781]
        return slice.elementsEqual("CD001".data(using: .ascii)!)
    }
    
    /// Detect if data is a DMG file
    static func isDMG(_ data: Data) -> Bool {
        guard data.count >= 4 else { return false }
        return data[0] == 0x78 && data[1] == 0x01 && data[2] == 0x73 && data[3] == 0x0D
    }
}

// MARK: - Progress Tracker

/// Track operation progress
class ProgressTracker: ObservableObject {
    @Published var progress: Double = 0
    @Published var isCancelled = false
    
    private var onProgress: ((Double) -> Void)?
    
    init(onProgress: ((Double) -> Void)? = nil) {
        self.onProgress = onProgress
    }
    
    func update(_ value: Double) {
        guard !isCancelled else { return }
        DispatchQueue.main.async {
            self.progress = min(max(value, 0), 1)
            self.onProgress?(self.progress)
        }
    }
    
    func cancel() {
        isCancelled = true
    }
    
    func reset() {
        progress = 0
        isCancelled = false
    }
}

// MARK: - Array Slice to Data

extension ArraySlice where Element == UInt8 {
    /// Convert slice to Data
    var data: Data {
        Data(self)
    }
}
