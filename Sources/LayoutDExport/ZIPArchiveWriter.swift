import Foundation

/// Minimal in-process ZIP32 writer used by IDML packaging.
///
/// IDML requires `mimetype` to be the first entry and stored without compression. The caller
/// controls entry order; this writer stores every entry, avoiding an external zip executable and
/// keeping the container implementation deterministic.
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
        let size: UInt32
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

            let size = UInt32(entry.data.count)
            let checksum = crc32(entry.data)
            let localHeaderOffset = UInt32(archive.count)

            archive.appendLE(UInt32(0x0403_4b50)) // local file header signature
            archive.appendLE(UInt16(20))          // version needed to extract
            archive.appendLE(UInt16(0x0800))      // UTF-8 path
            archive.appendLE(UInt16(0))           // stored (no compression)
            archive.appendLE(UInt16(0))           // DOS time
            archive.appendLE(UInt16(0x0021))      // DOS date: 1980-01-01
            archive.appendLE(checksum)
            archive.appendLE(size)
            archive.appendLE(size)
            archive.appendLE(UInt16(path.count))
            archive.appendLE(UInt16(0))           // extra field length
            archive.append(path)
            archive.append(entry.data)

            centralRecords.append(
                CentralRecord(path: path, crc32: checksum, size: size, localHeaderOffset: localHeaderOffset)
            )
        }

        guard archive.count <= Int(UInt32.max) else { throw ArchiveError.archiveTooLarge }
        let centralDirectoryOffset = UInt32(archive.count)

        for record in centralRecords {
            archive.appendLE(UInt32(0x0201_4b50)) // central directory signature
            archive.appendLE(UInt16(20))          // version made by
            archive.appendLE(UInt16(20))          // version needed to extract
            archive.appendLE(UInt16(0x0800))      // UTF-8 path
            archive.appendLE(UInt16(0))           // stored (no compression)
            archive.appendLE(UInt16(0))
            archive.appendLE(UInt16(0x0021))
            archive.appendLE(record.crc32)
            archive.appendLE(record.size)
            archive.appendLE(record.size)
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
