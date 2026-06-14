import Foundation

public enum ProjectFile {
    public static func encode(_ project: BookProject) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(project)
    }

    public static func decode(_ data: Data) throws -> BookProject {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(BookProject.self, from: data)
    }
}
