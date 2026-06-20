import Foundation

// MARK: - Date Extensions

extension Date {
    /// Format date for display
    var displayString: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: self)
    }
    
    /// Short date format
    var shortString: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter.string(from: self)
    }
}

// MARK: - Data Extensions

extension Data {
    /// Convert data to hex string
    var hexString: String {
        return map { String(format: "%02hhx", $0) }.joined()
    }
    
    /// Read UInt16 at offset (big-endian)
    func readUInt16(at offset: Int) -> UInt16? {
        guard offset + 2 <= count else { return nil }
        return UInt16(self[offset]) << 8 | UInt16(self[offset + 1])
    }
    
    /// Read UInt32 at offset (big-endian)
    func readUInt32(at offset: Int) -> UInt32? {
        guard offset + 4 <= count else { return nil }
        return UInt32(self[offset]) << 24 |
               UInt32(self[offset + 1]) << 16 |
               UInt32(self[offset + 2]) << 8 |
               UInt32(self[offset + 3])
    }
    
    /// Read UInt64 at offset (big-endian)
    func readUInt64(at offset: Int) -> UInt64? {
        guard offset + 8 <= count else { return nil }
        return UInt64(self[offset]) << 56 |
               UInt64(self[offset + 1]) << 48 |
               UInt64(self[offset + 2]) << 40 |
               UInt64(self[offset + 3]) << 32 |
               UInt64(self[offset + 4]) << 24 |
               UInt64(self[offset + 5]) << 16 |
               UInt64(self[offset + 6]) << 8 |
               UInt64(self[offset + 7])
    }
}

// MARK: - URL Extensions

extension URL {
    /// Get file size
    var fileSize: Int64? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path) else {
            return nil
        }
        return attributes[.size] as? Int64
    }
    
    /// Get formatted file size
    var formattedFileSize: String {
        guard let size = fileSize else { return "Unknown" }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
    
    /// Check if URL is a DC42 file
    var isDC42File: Bool {
        return pathExtension.lowercased() == "dc42"
    }
}

// MARK: - String Extensions

extension String {
    /// Trim whitespace and control characters
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
    }
    
    /// Convert MacRoman string to Swift String
    var fromMacRoman: String? {
        guard let data = data(using: .macOSRoman) else { return nil }
        return String(data: data, encoding: .utf8) ?? self
    }
}
