import Foundation
import Compression

/// Minimal in-process ZIP32 writer used by IDML packaging.
///
/// IDML requires `mimetype` to be the first entry and stored without compression. Every other
/// entry is Deflate-compressed (matching what InDesign itself writes), which shrinks the highly
/// repetitive IDML XML by ~80% and keeps the container small on disk. The caller controls entry
/// order; `mimetype` is detected by path and left stored. Falls back to stored for any entry that
/// does not compress smaller (e.g. tiny or already-compressed payloads).
struct ZIPArchiveWriter {
    struct Entry {
        let path: String
        let data: Data
    }

    enum ArchiveError: Error, LocalizedError {
        case tooManyEntries(Int)
        case entryTooLarge(path: String, size: Int)
        case archiveTooLarge
        case invalidPath(String)
        case duplicatePath(String)

        var errorDescription: String? {
            switch self {
            case .tooManyEntries(let count):
                return "ZIP32 supports at most \(UInt16.max) entries (received \(count))"
            case .entryTooLarge(let path, let size):
                return "ZIP32 entry is too large: \(path) (\(size) bytes)"
            case .archiveTooLarge:
                return "ZIP32 archive exceeds the 4 GiB format limit"
            case .invalidPath(let path):
                return "Invalid ZIP entry path: \(path)"
            case .duplicatePath(let path):
                return "Duplicate ZIP entry path: \(path)"
            }
        }
    }

    private struct CentralRecord {
        let path: Data
        let crc32: UInt32
        let compressedSize: UInt32
        let uncompressedSize: UInt32
        let method: UInt16
        let localHeaderOffset: UInt32
    }

    static func write(entries: [Entry], to outputURL: URL) throws {
        guard entries.count <= Int(UInt16.max) else {
            throw ArchiveError.tooManyEntries(entries.count)
        }

        var archive = Data()
        var centralRecords: [CentralRecord] = []
        var seenPaths = Set<String>()

        for entry in entries {
            guard !entry.path.isEmpty,
                  !entry.path.hasPrefix("/"),
                  !entry.path.contains("\\"),
                  !entry.path.split(separator: "/").contains("..") else {
                throw ArchiveError.invalidPath(entry.path)
            }
            guard seenPaths.insert(entry.path).inserted else {
                throw ArchiveError.duplicatePath(entry.path)
            }

            let path = Data(entry.path.utf8)
            guard path.count <= Int(UInt16.max) else {
                throw ArchiveError.invalidPath(entry.path)
            }
            guard entry.data.count <= Int(UInt32.max) else {
                throw ArchiveError.entryTooLarge(path: entry.path, size: entry.data.count)
            }
            guard archive.count <= Int(UInt32.max) else {
                throw ArchiveError.archiveTooLarge
            }

            let uncompressedSize = UInt32(entry.data.count)
            let checksum = crc32(entry.data)
            let localHeaderOffset = UInt32(archive.count)

            // `mimetype` must stay stored per the IDML/OCF spec; everything else Deflates when it helps.
            let payload: Data
            let method: UInt16
            if entry.path != "mimetype", let compressed = deflate(entry.data) {
                payload = compressed
                method = 8 // Deflate
            } else {
                payload = entry.data
                method = 0 // Stored
            }
            let compressedSize = UInt32(payload.count)

            archive.appendLE(UInt32(0x0403_4b50)) // local file header signature
            archive.appendLE(UInt16(20))          // version needed to extract
            archive.appendLE(UInt16(0x0800))      // UTF-8 path
            archive.appendLE(method)              // compression method
            archive.appendLE(UInt16(0))           // DOS time
            archive.appendLE(UInt16(0x0021))      // DOS date: 1980-01-01
            archive.appendLE(checksum)
            archive.appendLE(compressedSize)
            archive.appendLE(uncompressedSize)
            archive.appendLE(UInt16(path.count))
            archive.appendLE(UInt16(0))           // extra field length
            archive.append(path)
            archive.append(payload)

            centralRecords.append(
                CentralRecord(path: path, crc32: checksum, compressedSize: compressedSize,
                              uncompressedSize: uncompressedSize, method: method,
                              localHeaderOffset: localHeaderOffset)
            )
        }

        guard archive.count <= Int(UInt32.max) else { throw ArchiveError.archiveTooLarge }
        let centralDirectoryOffset = UInt32(archive.count)

        for record in centralRecords {
            archive.appendLE(UInt32(0x0201_4b50)) // central directory signature
            archive.appendLE(UInt16(20))          // version made by
            archive.appendLE(UInt16(20))          // version needed to extract
            archive.appendLE(UInt16(0x0800))      // UTF-8 path
            archive.appendLE(record.method)       // compression method
            archive.appendLE(UInt16(0))
            archive.appendLE(UInt16(0x0021))
            archive.appendLE(record.crc32)
            archive.appendLE(record.compressedSize)
            archive.appendLE(record.uncompressedSize)
            archive.appendLE(UInt16(record.path.count))
            archive.appendLE(UInt16(0))           // extra field length
            archive.appendLE(UInt16(0))           // comment length
            archive.appendLE(UInt16(0))           // disk number
            archive.appendLE(UInt16(0))           // internal attributes
            archive.appendLE(UInt32(0))           // external attributes
            archive.appendLE(record.localHeaderOffset)
            archive.append(record.path)
        }

        guard archive.count <= Int(UInt32.max) else { throw ArchiveError.archiveTooLarge }
        let centralDirectorySize = UInt32(archive.count) - centralDirectoryOffset
        let entryCount = UInt16(entries.count)
        archive.appendLE(UInt32(0x0605_4b50))
        archive.appendLE(UInt16(0))               // current disk
        archive.appendLE(UInt16(0))               // central directory disk
        archive.appendLE(entryCount)
        archive.appendLE(entryCount)
        archive.appendLE(centralDirectorySize)
        archive.appendLE(centralDirectoryOffset)
        archive.appendLE(UInt16(0))               // comment length

        let fileManager = FileManager.default
        let parent = outputURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        let temporaryURL = parent.appendingPathComponent(".\(outputURL.lastPathComponent).\(UUID().uuidString).tmp")
        defer { try? fileManager.removeItem(at: temporaryURL) }
        try archive.write(to: temporaryURL, options: .atomic)

        if fileManager.fileExists(atPath: outputURL.path) {
            _ = try fileManager.replaceItemAt(outputURL, withItemAt: temporaryURL)
        } else {
            try fileManager.moveItem(at: temporaryURL, to: outputURL)
        }
    }

    /// Raw DEFLATE (RFC 1951) via Apple's Compression framework — `COMPRESSION_ZLIB` emits the
    /// bare deflate stream ZIP method 8 expects (no zlib header/adler checksum). Returns nil when
    /// the input is empty or does not shrink, so the caller falls back to storing it uncompressed.
    private static func deflate(_ data: Data) -> Data? {
        guard !data.isEmpty else { return nil }
        let capacity = data.count
        var destination = Data(count: capacity)
        let written = destination.withUnsafeMutableBytes { destinationBuffer -> Int in
            data.withUnsafeBytes { sourceBuffer -> Int in
                guard let destinationBase = destinationBuffer.bindMemory(to: UInt8.self).baseAddress,
                      let sourceBase = sourceBuffer.bindMemory(to: UInt8.self).baseAddress else {
                    return 0
                }
                return compression_encode_buffer(destinationBase, capacity,
                                                 sourceBase, data.count,
                                                 nil, COMPRESSION_ZLIB)
            }
        }
        guard written > 0, written < data.count else { return nil }
        destination.removeSubrange(written..<destination.count)
        return destination
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc = UInt32.max
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc >> 1) ^ ((crc & 1) == 0 ? 0 : 0xedb8_8320)
            }
        }
        return ~crc
    }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}
