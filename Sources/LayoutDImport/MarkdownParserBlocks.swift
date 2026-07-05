import Foundation
import LayoutDCore

extension MarkdownParser {
    mutating func flushParagraphBuffer() {
        guard !paragraphBuffer.isEmpty else {
            return
        }
        let role = pendingContentRole
        currentParagraphs.append(makeParagraph(kind: role?.paragraphKind ?? .body, markdown: paragraphBuffer.joined(separator: " "), styleId: role?.styleID ?? StyleID.body.rawValue))
        if role?.isSingleParagraph == true { pendingContentRole = nil }   // 标题/抽言只管这一段
        paragraphBuffer.removeAll(keepingCapacity: true)
    }

    mutating func flushCalloutBuffer() {
        guard !calloutBuffer.isEmpty else {
            return
        }
        currentParagraphs.append(
            makeParagraph(
                kind: .callout,
                markdown: calloutBuffer.joined(separator: " "),
                styleId: StyleID.callout.rawValue
            )
        )
        calloutBuffer.removeAll(keepingCapacity: true)
    }

    mutating func flushTableBuffer() {
        guard !tableBuffer.isEmpty else {
            return
        }

        let rows = tableBuffer
            .filter { !isTableSeparatorLine($0) }
            .map(tableCells)
            .filter { !$0.isEmpty }

        if !rows.isEmpty {
            // 保留结构化行列供 IDML 导出原生 <Table>；每格解析行内 Markdown，
            // 同时留下归一化文本（tableCells）与行内格式（tableCellRuns，偏移针对该格文本）。
            // `text` 维持拍平降级（布局/预览暂不识别网格时仍能显示）。
            let parsedRows = rows.map { $0.map(parseInlineMarkdown) }
            let normalizedRows = parsedRows.map { $0.map(\.text) }
            let cellRuns = parsedRows.map { $0.map(\.runs) }
            let text = normalizedRows.map { $0.joined(separator: "    ") }.joined(separator: "\n")
            let hasRuns = cellRuns.contains { $0.contains { !$0.isEmpty } }
            currentParagraphs.append(
                Paragraph(kind: .table, text: text, styleId: StyleID.body.rawValue,
                          tableCells: normalizedRows, tableCellRuns: hasRuns ? cellRuns : nil)
            )
        }

        tableBuffer.removeAll(keepingCapacity: true)
    }

    mutating func flushSection() {
        flushSideNoteBuffer()
        postProcessFootnotesAndSideNotes()
        guard !currentParagraphs.isEmpty else {
            return
        }
        sections.append(
            BookSection(
                title: currentSectionTitle,
                stories: [
                    Story(title: currentSectionTitle, paragraphs: currentParagraphs)
                ]
            )
        )
        currentParagraphs.removeAll(keepingCapacity: true)
    }

    mutating func addQuoteLine(_ line: String) {
        let upperLine = line.uppercased()
        if upperLine.hasPrefix("[!SIDE]") {
            flushCalloutBuffer()
            flushSideNoteBuffer()
            let suffix = String(line.dropFirst(7)).trimmed
            var cleanSuffix = suffix
            if cleanSuffix.hasPrefix(":") || cleanSuffix.hasPrefix("：") {
                cleanSuffix = String(cleanSuffix.dropFirst()).trimmed
            }
            sideNoteBuffer.append(cleanSuffix)
            return
        }

        if let calloutStart = parseAdmonitionStart(line) {
            flushCalloutBuffer()
            flushSideNoteBuffer()
            calloutBuffer.append(calloutStart)
            return
        }

        if !sideNoteBuffer.isEmpty {
            sideNoteBuffer.append(line)
            return
        }

        if !calloutBuffer.isEmpty {
            calloutBuffer.append(line)
            return
        }

        currentParagraphs.append(
            makeParagraph(
                kind: .quote,
                markdown: line,
                styleId: StyleID.callout.rawValue
            )
        )
    }

    mutating func flushSideNoteBuffer() {
        guard !sideNoteBuffer.isEmpty else {
            return
        }
        let text = normalizeInlineMarkdown(sideNoteBuffer.joined(separator: " "))
        let sideNoteParagraph = Paragraph(
            id: UUID(),
            kind: .sideNote,
            text: text,
            styleId: "sideNote"
        )
        
        var targetIndex: Int?
        for i in currentParagraphs.indices.reversed() {
            let p = currentParagraphs[i]
            switch p.kind {
            case .footnote, .sideNote:
                continue
            default:
                targetIndex = i
                break
            }
            if targetIndex != nil { break }
        }
        
        if let idx = targetIndex {
            if currentParagraphs[idx].anchoredSideNoteIds == nil {
                currentParagraphs[idx].anchoredSideNoteIds = []
            }
            currentParagraphs[idx].anchoredSideNoteIds?.append(sideNoteParagraph.id)
            currentParagraphs.append(sideNoteParagraph)
        } else {
            currentParagraphs.append(sideNoteParagraph)
        }
        sideNoteBuffer.removeAll(keepingCapacity: true)
    }

    func superscriptString(for number: Int) -> String {
        let superscripts = [
            0: "⁰", 1: "¹", 2: "²", 3: "³", 4: "⁴",
            5: "⁵", 6: "⁶", 7: "⁷", 8: "⁸", 9: "⁹"
        ]
        let digits = String(number).compactMap { Int(String($0)) }
        return digits.map { superscripts[$0] ?? "" }.joined()
    }

    mutating func postProcessFootnotesAndSideNotes() {
        var footnoteParagraphsToAppend: [Paragraph] = []
        
        for i in currentParagraphs.indices {
            let paragraph = currentParagraphs[i]
            switch paragraph.kind {
            case .footnote, .sideNote:
                continue
            default:
                break
            }
            
            let text = paragraph.text
            let pattern = "\\[\\^([^\\]]+)\\]"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { continue }
            
            let matches = regex.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text))
            guard !matches.isEmpty else { continue }
            
            var newText = text
            var anchoredIds: [UUID] = []
            
            for match in matches.reversed() {
                guard let idRange = Range(match.range(at: 1), in: text) else { continue }
                let id = String(text[idRange]).trimmed
                
                guard let content = footnoteDefinitions[id] else { continue }
                
                let num: Int
                if let existingNum = footnoteMap[id] {
                    num = existingNum
                } else {
                    num = nextFootnoteNumber
                    footnoteMap[id] = num
                    nextFootnoteNumber += 1
                    
                    let fnPara = Paragraph(
                        id: UUID(),
                        kind: .footnote(number: num),
                        text: content,
                        styleId: "footnote"
                    )
                    footnoteParagraphsToAppend.append(fnPara)
                }
                
                let superscript = superscriptString(for: num)
                
                if let matchRange = Range(match.range(at: 0), in: newText) {
                    newText.replaceSubrange(matchRange, with: superscript)
                }
                
                if let fnPara = footnoteParagraphsToAppend.first(where: {
                    if case .footnote(let n) = $0.kind { return n == num }
                    return false
                }) {
                    anchoredIds.insert(fnPara.id, at: 0)
                }
            }
            
            if !anchoredIds.isEmpty {
                currentParagraphs[i].text = newText
                currentParagraphs[i].anchoredFootnoteIds = anchoredIds
            }
        }
        
        currentParagraphs.append(contentsOf: footnoteParagraphsToAppend)
    }

    mutating func collectAndRemoveFootnoteDefinitions(from lines: inout [String]) -> [String: String] {
        var footnoteDefs: [String: String] = [:]
        var indicesToRemove = IndexSet()
        var currentFootnoteId: String? = nil
        
        for index in lines.indices {
            let line = lines[index]
            if line.hasPrefix("[^") {
                if let colonIndex = line.firstIndex(of: "]"),
                   line.index(after: colonIndex) < line.endIndex,
                   line[line.index(after: colonIndex)] == ":" {
                    let idStart = line.index(line.startIndex, offsetBy: 2)
                    let id = String(line[idStart..<colonIndex]).trimmed
                    let contentStart = line.index(colonIndex, offsetBy: 2, limitedBy: line.endIndex) ?? line.endIndex
                    let content = contentStart < line.endIndex ? String(line[contentStart...]).trimmed : ""
                    footnoteDefs[id] = content
                    currentFootnoteId = id
                    indicesToRemove.insert(index)
                    continue
                }
            }
            
            if let id = currentFootnoteId {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if line.hasPrefix("    ") || line.hasPrefix("\t") {
                    let existing = footnoteDefs[id] ?? ""
                    footnoteDefs[id] = existing + (existing.isEmpty ? "" : " ") + trimmed
                    indicesToRemove.insert(index)
                    continue
                } else if line.isEmpty {
                    var nextIsIndented = false
                    for nextIndex in (index + 1)..<lines.count {
                        let nextLine = lines[nextIndex]
                        if nextLine.trimmingCharacters(in: .whitespaces).isEmpty {
                            continue
                        }
                        if nextLine.hasPrefix("    ") || nextLine.hasPrefix("\t") {
                            nextIsIndented = true
                        }
                        break
                    }
                    if nextIsIndented {
                        indicesToRemove.insert(index)
                        continue
                    } else {
                        currentFootnoteId = nil
                    }
                } else {
                    currentFootnoteId = nil
                }
            }
        }
        
        for index in indicesToRemove.sorted(by: >) {
            lines.remove(at: index)
        }
        return footnoteDefs
    }

    mutating func flushAllBuffers() {
        flushParagraphBuffer()
        flushCalloutBuffer()
        flushTableBuffer()
        flushSideNoteBuffer()
    }

    func parseHeading(_ line: String) -> MarkdownHeading? {
        var level = 0
        for character in line {
            if character == "#" {
                level += 1
                continue
            }
            break
        }

        guard (1...6).contains(level) else {
            return nil
        }

        let markerEnd = line.index(line.startIndex, offsetBy: level)
        guard markerEnd < line.endIndex, line[markerEnd] == " " else {
            return nil
        }

        let text = String(line[line.index(after: markerEnd)...]).trimmed
        guard !text.isEmpty else {
            return nil
        }

        return MarkdownHeading(level: level, text: text)
    }

    func parseSetextHeading(line: String, nextLine: String?) -> MarkdownHeading? {
        guard let nextLine,
              !line.isEmpty,
              !line.hasPrefix("> "),
              !isTableLine(line),
              parseImage(line) == nil,
              parseListItem(line) == nil else {
            return nil
        }

        let compactUnderline = nextLine.replacingOccurrences(of: " ", with: "")
        guard compactUnderline.count >= 3 else {
            return nil
        }

        let level: Int
        if compactUnderline.allSatisfy({ $0 == "=" }) {
            level = 1
        } else if compactUnderline.allSatisfy({ $0 == "-" }) {
            level = 2
        } else {
            return nil
        }

        let text = line
        guard !text.isEmpty else {
            return nil
        }
        return MarkdownHeading(level: level, text: text)
    }

    func parseListItem(_ line: String) -> String? {
        if line.hasPrefix("- ") || line.hasPrefix("* ") {
            let text = String(line.dropFirst(2)).trimmed
            return text.isEmpty ? nil : text
        }

        var digitCount = 0
        for character in line {
            if character.isNumber {
                digitCount += 1
                continue
            }
            break
        }

        guard digitCount > 0 else {
            return nil
        }

        let markerIndex = line.index(line.startIndex, offsetBy: digitCount)
        guard markerIndex < line.endIndex, line[markerIndex] == "." || line[markerIndex] == ")" else {
            return nil
        }

        let textStart = line.index(after: markerIndex)
        guard textStart < line.endIndex, line[textStart] == " " else {
            return nil
        }

        let marker = String(line[..<textStart]).trimmed
        let text = String(line[line.index(after: textStart)...]).trimmed
        guard !text.isEmpty else {
            return nil
        }
        return "\(marker) \(text)"
    }

    func isNonContentLine(_ line: String) -> Bool {
        let compactLine = line.replacingOccurrences(of: " ", with: "")
        guard compactLine.count >= 3 else {
            return false
        }

        return compactLine.allSatisfy { $0 == "-" }
            || compactLine.allSatisfy { $0 == "*" }
            || compactLine.allSatisfy { $0 == "_" }
    }

    mutating func shouldSkipHTMLCommentLine(_ line: String) -> Bool {
        if isInsideHTMLComment {
            if line.contains("-->") {
                isInsideHTMLComment = false
            }
            return true
        }

        guard let start = line.range(of: "<!--") else {
            return false
        }

        let afterStart = line[start.upperBound...]
        if !afterStart.contains("-->") {
            isInsideHTMLComment = true
        }
        return true
    }

    func isTableLine(_ line: String) -> Bool {
        line.hasPrefix("|") && line.hasSuffix("|") && line.dropFirst().dropLast().contains("|")
    }

    func isTableSeparatorLine(_ line: String) -> Bool {
        let normalized = line
            .replacingOccurrences(of: "|", with: "")
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
            .trimmingCharacters(in: .whitespaces)
        return normalized.isEmpty
    }

    func tableCells(_ line: String) -> [String] {
        var trimmedLine = line.trimmed
        if trimmedLine.hasPrefix("|") {
            trimmedLine.removeFirst()
        }
        if trimmedLine.hasSuffix("|") {
            trimmedLine.removeLast()
        }

        // 返回原始单元格 Markdown（不在此归一化）；归一化与行内 run 解析由
        // flushTableBuffer 统一做，以便同时拿到剥离文本与行内格式（粗/斜/傍点）。
        return trimmedLine
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { String($0).trimmed }
    }


    func parseAdmonitionStart(_ line: String) -> String? {
        guard line.hasPrefix("[!"), let closing = line.firstIndex(of: "]") else {
            return nil
        }

        let markerStart = line.index(line.startIndex, offsetBy: 2)
        let marker = String(line[markerStart..<closing]).uppercased()
        let title = String(line[line.index(after: closing)...]).trimmed
        let label = admonitionLabel(marker)
        guard !label.isEmpty else {
            return nil
        }

        return title.isEmpty ? label : "\(label)：\(title)"
    }

    func admonitionLabel(_ marker: String) -> String {
        switch marker {
        case "NOTE":
            return "知识点"
        case "TIP":
            return "提示"
        case "INFO":
            return "背景"
        case "EXAMPLE":
            return "例子"
        case "WARNING", "CAUTION":
            return "注意"
        default:
            return marker
        }
    }
}

struct MarkdownHeading {
    var level: Int
    var text: String
}
