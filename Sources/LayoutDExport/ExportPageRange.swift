import Foundation

enum ExportPageRange {
    static func parse(_ rangeString: String?, maxPages: Int) -> Set<Int> {
        guard maxPages > 0 else {
            return []
        }
        guard let rangeString else {
            return Set(1...maxPages)
        }

        let cleaned = rangeString.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty || cleaned == "全部" || cleaned.lowercased() == "all" {
            return Set(1...maxPages)
        }

        var pages = Set<Int>()
        for part in cleaned.split(separator: ",") {
            let trimmedPart = part.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedPart.contains("-") {
                let rangeParts = trimmedPart.split(separator: "-")
                if rangeParts.count == 2,
                   let start = Int(rangeParts[0].trimmingCharacters(in: .whitespaces)),
                   let end = Int(rangeParts[1].trimmingCharacters(in: .whitespaces)) {
                    for page in min(start, end)...max(start, end) where page >= 1 && page <= maxPages {
                        pages.insert(page)
                    }
                }
            } else if let page = Int(trimmedPart), page >= 1, page <= maxPages {
                pages.insert(page)
            }
        }

        return pages.isEmpty ? Set(1...maxPages) : pages
    }
}
