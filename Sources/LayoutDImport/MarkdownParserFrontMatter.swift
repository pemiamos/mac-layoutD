import Foundation
import LayoutDCore

extension MarkdownParser {
    func extractFrontMatter(from lines: inout [String]) -> FrontMatter {
        guard lines.first?.trimmingCharacters(in: .whitespacesAndNewlines) == "---" else {
            return FrontMatter()
        }

        var values: [String: String] = [:]
        var endIndex: Int?

        for index in 1..<lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
            if line == "---" {
                endIndex = index
                break
            }

            guard let separator = line.firstIndex(of: ":") else {
                continue
            }

            let key = String(line[..<separator]).trimmed.lowercased()
            let value = String(line[line.index(after: separator)...]).trimmed.trimmedQuotes
            values[key] = value
        }

        if let endIndex {
            lines.removeSubrange(0...endIndex)
        }

        return FrontMatter(
            title: values["title"],
            subtitle: values["subtitle"],
            author: values["author"],
            publisher: values["publisher"],
            isbn: values["isbn"],
            series: values["series"],
            keywords: parseKeywords(values["keywords"] ?? values["tags"]),
            pageSetup: parsePageSetup(values)
        )
    }

    /// Manuscripts occasionally put a YAML-like metadata block before a later chapter.
    /// This importer has no per-section page setup, so consume that metadata rather than
    /// letting it leak into the book text. A title still has document meaning: turn it
    /// into a level-one heading so the normal section parser owns the boundary.
    func consumingSubsequentFrontMatter(in lines: [String]) -> [String] {
        var result: [String] = []
        var index = 0

        while index < lines.count {
            guard isFrontMatterDelimiter(lines[index]), isSectionBoundary(before: result),
                  let endIndex = subsequentFrontMatterEnd(in: lines, startingAt: index),
                  let values = frontMatterValues(in: lines[(index + 1)..<endIndex])
            else {
                result.append(lines[index])
                index += 1
                continue
            }

            if let title = values["title"], !title.isEmpty {
                result.append("# \(title)")
            }
            index = endIndex + 1
        }

        return result
    }

    func isFrontMatterDelimiter(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespacesAndNewlines) == "---"
    }

    func isSectionBoundary(before lines: [String]) -> Bool {
        guard let previous = lines.last else {
            return true
        }
        return previous.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func subsequentFrontMatterEnd(in lines: [String], startingAt startIndex: Int) -> Int? {
        let searchStart = startIndex + 1
        guard searchStart < lines.count else {
            return nil
        }

        for index in searchStart..<lines.count where isFrontMatterDelimiter(lines[index]) {
            return index
        }
        return nil
    }

    func frontMatterValues(in lines: ArraySlice<String>) -> [String: String]? {
        guard !lines.isEmpty else {
            return nil
        }

        var values: [String: String] = [:]
        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, let separator = line.firstIndex(of: ":") else {
                return nil
            }

            let key = String(line[..<separator]).trimmed.lowercased()
            let value = String(line[line.index(after: separator)...]).trimmed.trimmedQuotes
            guard !key.isEmpty else {
                return nil
            }
            values[key] = value
        }
        return values
    }

    func parseKeywords(_ value: String?) -> [String] {
        guard let value else {
            return []
        }

        return value
            .components(separatedBy: CharacterSet(charactersIn: ",;，；"))
            .map(\.trimmed)
            .filter { !$0.isEmpty }
    }

    func parsePageSetup(_ values: [String: String]) -> PageSetup? {
        let hasPageSetupValues = values["columns"] != nil
            || values["page_width_mm"] != nil
            || values["page_height_mm"] != nil
            || values["page"] != nil
            || values["margins"] != nil
            || values["margin_top_mm"] != nil
            || values["margin_right_mm"] != nil
            || values["margin_bottom_mm"] != nil
            || values["margin_left_mm"] != nil
            || values["gutter_mm"] != nil
            || values["baseline_grid_pt"] != nil
            || values["bleed_mm"] != nil
            || values["layout_direction"] != nil
        guard hasPageSetupValues else {
            return nil
        }

        var setup = PageSetup.scienceBookDefault
        if let direction = values["layout_direction"]?.lowercased() {
            setup.layoutDirection = (direction == "vertical") ? .vertical : .horizontal
        }
        if let columns = values["columns"].flatMap(Int.init), columns > 0 {
            setup.columns = min(columns, 4)
        }

        let pagePair = parsePageSize(values)
        if let pagePair {
            setup.pageSize = PageSize(
                width: pagePair.widthMM.mmToPoints,
                height: pagePair.heightMM.mmToPoints,
                label: "\(formatMM(pagePair.widthMM))mm x \(formatMM(pagePair.heightMM))mm"
            )
        }

        if let margins = parseMargins(values) {
            setup.margins = margins
        }

        if let gutterMM = values["gutter_mm"].flatMap(Double.init), gutterMM >= 0 {
            setup.gutter = gutterMM.mmToPoints
        }

        if let baselineGrid = values["baseline_grid_pt"].flatMap(Double.init), baselineGrid > 0 {
            setup.baselineGrid = baselineGrid
        }

        if let bleedMM = values["bleed_mm"].flatMap(Double.init), bleedMM >= 0 {
            setup.bleedMM = bleedMM
        }

        return setup
    }

    func parseMargins(_ values: [String: String]) -> PageMargins? {
        let defaultMargins = PageSetup.scienceBookDefault.margins
        var top = values["margin_top_mm"].flatMap(Double.init)?.mmToPoints ?? defaultMargins.top
        var right = values["margin_right_mm"].flatMap(Double.init)?.mmToPoints ?? defaultMargins.right
        var bottom = values["margin_bottom_mm"].flatMap(Double.init)?.mmToPoints ?? defaultMargins.bottom
        var left = values["margin_left_mm"].flatMap(Double.init)?.mmToPoints ?? defaultMargins.left

        if let shorthand = values["margins"] {
            let parts = shorthand
                .lowercased()
                .replacingOccurrences(of: "mm", with: "")
                .replacingOccurrences(of: ",", with: " ")
                .split(separator: " ")
                .compactMap { Double($0) }

            switch parts.count {
            case 1:
                top = parts[0].mmToPoints
                right = top
                bottom = top
                left = top
            case 2:
                top = parts[0].mmToPoints
                bottom = top
                right = parts[1].mmToPoints
                left = right
            case 4:
                top = parts[0].mmToPoints
                right = parts[1].mmToPoints
                bottom = parts[2].mmToPoints
                left = parts[3].mmToPoints
            default:
                break
            }
        }

        guard top >= 0, right >= 0, bottom >= 0, left >= 0 else {
            return nil
        }

        return PageMargins(top: top, right: right, bottom: bottom, left: left)
    }

    func parsePageSize(_ values: [String: String]) -> (widthMM: Double, heightMM: Double)? {
        if let width = values["page_width_mm"].flatMap(Double.init),
           let height = values["page_height_mm"].flatMap(Double.init),
           width > 0,
           height > 0 {
            return (width, height)
        }

        guard let page = values["page"]?.lowercased() else {
            return nil
        }

        let normalized = page
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "mm", with: "")
            .replacingOccurrences(of: "×", with: "x")
        let parts = normalized.split(separator: "x").compactMap { Double($0) }
        guard parts.count == 2, parts[0] > 0, parts[1] > 0 else {
            return nil
        }
        return (parts[0], parts[1])
    }

    func formatMM(_ value: Double) -> String {
        value.rounded() == value ? "\(Int(value))" : String(format: "%.1f", value)
    }
}

struct FrontMatter {
    var title: String?
    var subtitle: String?
    var author: String?
    var publisher: String?
    var isbn: String?
    var series: String?
    var keywords: [String] = []
    var pageSetup: PageSetup?
}

extension Double {
    var mmToPoints: Double {
        self / 25.4 * 72
    }
}
