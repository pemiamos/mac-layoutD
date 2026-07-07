import CoreText
import Foundation
import LayoutDCore

extension LayoutContext {
    var isVertical: Bool {
        project.pageSetup.layoutDirection == .vertical
    }

    var contentHeight: Double {
        let margins = project.resolvedMargins(for: currentAbsolutePageNumber)
        return project.pageSetup.pageSize.height - margins.top - margins.bottom
    }

    var currentAbsolutePageNumber: Int {
        absolutePageNumber(for: currentPage.number)
    }

    /// Converts a content-relative page number (1-based, content pages only) into
    /// the absolute book page number that page setup, plans, and preflight use.
    func absolutePageNumber(for contentPageNumber: Int) -> Int {
        contentPageNumber + frontMatterPageCount(for: project)
    }

    var contentWidth: Double {
        let setup = project.pageSetup
        let margins = project.resolvedMargins(for: currentAbsolutePageNumber)
        return setup.pageSize.width - margins.left - margins.right
    }

    var columnWidth: Double {
        if isVertical {
            return contentWidth
        } else {
            let columns = project.resolvedColumns(for: currentAbsolutePageNumber)
            let totalGutter = Double(max(columns - 1, 0)) * project.resolvedGutter(for: currentAbsolutePageNumber)
            return (contentWidth - totalGutter) / Double(max(columns, 1))
        }
    }

    var columnTextHeight: Double {
        if isVertical {
            let columns = project.resolvedColumns(for: currentAbsolutePageNumber)
            let totalGutter = Double(max(columns - 1, 0)) * project.resolvedGutter(for: currentAbsolutePageNumber)
            return (contentHeight - totalGutter) / Double(max(columns, 1))
        } else {
            let margins = project.resolvedMargins(for: currentAbsolutePageNumber)
            return resolvedBottomLimit(for: currentAbsolutePageNumber) - margins.top
        }
    }

    var remainingColumnHeight: Double {
        if isVertical {
            let leftLimit = pageLeftMargin(for: currentAbsolutePageNumber)
            return cursorX - leftLimit
        } else {
            return resolvedBottomLimit(for: currentAbsolutePageNumber) - cursorY
        }
    }

    func resolvedBottomLimit(for pageNumber: Int) -> Double {
        let margins = project.resolvedMargins(for: pageNumber)
        let fnHeight = currentPageFootnoteHeight
        let baseBottomLimit = project.pageSetup.pageSize.height - margins.bottom
        if fnHeight > 0 {
            return baseBottomLimit - fnHeight - 24
        }
        return baseBottomLimit
    }

    func pageLeftMargin(for pageNumber: Int) -> Double {
        let setup = project.pageSetup
        let margins = project.resolvedMargins(for: pageNumber)
        if setup.facingPages {
            return pageNumber % 2 == 1 ? margins.left : margins.right
        }
        return margins.left
    }

    func pageRightMargin(for pageNumber: Int) -> Double {
        let setup = project.pageSetup
        let margins = project.resolvedMargins(for: pageNumber)
        if setup.facingPages {
            return pageNumber % 2 == 1 ? margins.right : margins.left
        }
        return margins.right
    }

    mutating func advanceIfNeeded(_ requiredHeight: Double) {
        let bottomLimit = resolvedBottomLimit(for: currentAbsolutePageNumber)
        guard cursorY + requiredHeight > bottomLimit else { return }

        advanceToNextColumnOrPage()
    }

    mutating func advanceToNextColumnOrPage() {
        let columns = project.resolvedColumns(for: currentAbsolutePageNumber)
        if currentColumn + 1 < columns {
            currentColumn += 1
            let actualPageNumber = currentAbsolutePageNumber
            let margins = project.resolvedMargins(for: actualPageNumber)
            if isVertical {
                let rowHeight = columnTextHeight
                let gutter = project.resolvedGutter(for: actualPageNumber)
                currentColumnTopY = margins.top + Double(currentColumn) * (rowHeight + gutter)
                cursorX = project.pageSetup.pageSize.width - pageRightMargin(for: actualPageNumber)
                cursorY = currentColumnTopY
            } else {
                cursorX = pageLeftMargin(for: actualPageNumber) + Double(currentColumn) * (columnWidth + project.resolvedGutter(for: actualPageNumber))
                cursorY = currentColumnTopY
            }
        } else {
            advanceToNextPage()
        }
    }

    mutating func advanceToNextPage() {
        layoutFootnotesAndSideNotesOnCurrentPage()
        pages.append(currentPage)
        let newPageNumber = pages.count + 1
        currentPage = LaidOutPage(number: newPageNumber)
        if let pending = pendingPageFrames[newPageNumber] {
            currentPage.frames.append(contentsOf: pending)
            pendingPageFrames.removeValue(forKey: newPageNumber)
        }
        currentColumn = 0
        let absPageNum = absolutePageNumber(for: newPageNumber)
        let margins = project.resolvedMargins(for: absPageNum)
        if isVertical {
            cursorX = project.pageSetup.pageSize.width - pageRightMargin(for: absPageNum)
            cursorY = margins.top
            currentColumnTopY = margins.top
        } else {
            cursorX = pageLeftMargin(for: absPageNum)
            cursorY = margins.top
            currentColumnTopY = margins.top
        }
        addRunningHeader(project.metadata.title)
        
        applyPlanIfPresent()
    }

    mutating func snapToBaseline() {
        let grid = project.resolvedBaselineGrid
        cursorY = ceil(cursorY / grid) * grid
    }
}
