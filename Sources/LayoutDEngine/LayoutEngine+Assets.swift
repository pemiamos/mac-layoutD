import CoreText
import Foundation
import LayoutDCore

extension LayoutContext {
    mutating func addAsset(_ asset: Asset, sourceParagraphId: UUID? = nil) {
        if asset.role == .spread {
            addSpreadAsset(asset)
            return
        }
        placedAssetIds.insert(asset.id)
        figureCounter += 1
        let imageWidth = imageWidth(for: asset)
        let desiredHeight = imageHeight(for: asset, width: imageWidth)
        
        let isUnderlay = asset.effectiveWrapMode == .underlay
        let wrapModeValue: AssetWrapMode? = isUnderlay ? .underlay : nil

        if isUnderlay {
            let imageRect = Rect(x: cursorX, y: cursorY, width: imageWidth, height: desiredHeight)
            currentPage.frames.append(PageFrame(
                kind: .image,
                rect: imageRect,
                content: .asset(asset.id),
                sourceParagraphId: sourceParagraphId,
                wrapMode: wrapModeValue
            ))

            if let caption = asset.caption {
                let captionText = numberedCaption(caption, number: figureCounter)
                let captionRect = Rect(x: cursorX, y: cursorY + desiredHeight + 4, width: imageWidth, height: 28)
                currentPage.frames.append(
                    PageFrame(
                        kind: .caption,
                        rect: captionRect,
                        styleId: StyleID.caption.rawValue,
                        content: .text(captionText),
                        sourceParagraphId: sourceParagraphId,
                        wrapMode: wrapModeValue
                    )
                )
            } else {
                issues.append(
                    LayoutIssue(
                        severity: .warning,
                        message: "图片 \(asset.fileName) 缺少图注",
                        category: .assets,
                        pageNumber: currentPage.number
                    )
                )
            }

            if let effectiveDPI = effectiveDPI(asset: asset, widthPoints: imageRect.width), effectiveDPI < 220 {
                issues.append(
                    LayoutIssue(
                        severity: .warning,
                        message: "图片 \(asset.fileName) 预计印刷分辨率低于 220 DPI",
                        category: .assets,
                        pageNumber: currentPage.number
                    )
                )
            }
            return
        }

        if shouldSpanColumns(asset) {
            prepareWideAssetPlacement(requiredHeight: desiredHeight + 42)
        } else {
            advanceIfNeeded(desiredHeight + 42)
        }

        let imageRect = Rect(x: cursorX, y: cursorY, width: imageWidth, height: desiredHeight)
        currentPage.frames.append(PageFrame(kind: .image, rect: imageRect, content: .asset(asset.id), sourceParagraphId: sourceParagraphId))
        cursorY += desiredHeight + 4

        if let caption = asset.caption {
            let caption = numberedCaption(caption, number: figureCounter)
            let captionRect = Rect(x: cursorX, y: cursorY, width: imageWidth, height: 28)
            currentPage.frames.append(
                PageFrame(kind: .caption, rect: captionRect, styleId: StyleID.caption.rawValue, content: .text(caption), sourceParagraphId: sourceParagraphId)
            )
            cursorY += 34
        } else {
            issues.append(
                LayoutIssue(
                    severity: .warning,
                    message: "图片 \(asset.fileName) 缺少图注",
                    category: .assets,
                    pageNumber: currentPage.number
                )
            )
        }

        if let effectiveDPI = effectiveDPI(asset: asset, widthPoints: imageRect.width), effectiveDPI < 220 {
            issues.append(
                LayoutIssue(
                    severity: .warning,
                    message: "图片 \(asset.fileName) 预计印刷分辨率低于 220 DPI",
                    category: .assets,
                    pageNumber: currentPage.number
                )
            )
        }

        snapToBaseline()
        if shouldSpanColumns(asset) {
            currentColumnTopY = cursorY
        }
    }

    mutating func addSpreadAsset(_ asset: Asset) {
        placedAssetIds.insert(asset.id)
        figureCounter += 1
        
        let setup = project.pageSetup
        let pageWidth = setup.pageSize.width
        let leftMargin = pageLeftMargin(for: 2)
        let rightMargin = pageRightMargin(for: 3)
        let totalWidth = (pageWidth - leftMargin) + (pageWidth - rightMargin)
        
        let desiredHeight = imageHeight(for: asset, width: totalWidth)
        let requiredHeight = desiredHeight + 42
        
        let isUnderlay = asset.effectiveWrapMode == .underlay
        let wrapModeValue: AssetWrapMode? = isUnderlay ? .underlay : nil

        if isUnderlay {
            var tempContext = self
            if tempContext.currentAbsolutePageNumber % 2 == 1 {
                tempContext.advanceToNextPage()
            }

            let bottomLimit = tempContext.resolvedBottomLimit(for: tempContext.currentAbsolutePageNumber)
            if tempContext.cursorY + requiredHeight > bottomLimit {
                tempContext.advanceToNextPage()
                tempContext.advanceToNextPage()
            }
            
            let targetLeftPageNum = tempContext.currentPage.number
            let targetRightPageNum = targetLeftPageNum + 1
            let targetY = tempContext.cursorY
            
            let leftX = pageLeftMargin(for: tempContext.currentAbsolutePageNumber)
            let leftWidth = pageWidth - leftX
            let leftRect = Rect(x: leftX, y: targetY, width: leftWidth, height: desiredHeight)
            let leftFrame = PageFrame(
                kind: .image,
                rect: leftRect,
                content: .spreadAsset(assetId: asset.id, isLeftHalf: true),
                wrapMode: wrapModeValue
            )
            
            let rightWidth = pageWidth - pageRightMargin(for: tempContext.currentAbsolutePageNumber + 1)
            let rightRect = Rect(x: 0, y: targetY, width: rightWidth, height: desiredHeight)
            let rightFrame = PageFrame(
                kind: .image,
                rect: rightRect,
                content: .spreadAsset(assetId: asset.id, isLeftHalf: false),
                wrapMode: wrapModeValue
            )
            
            var captionFrame: PageFrame? = nil
            if let caption = asset.caption {
                let captionText = numberedCaption(caption, number: figureCounter)
                let captionRect = Rect(x: 0, y: targetY + desiredHeight + 4, width: rightWidth, height: 28)
                captionFrame = PageFrame(
                    kind: .caption,
                    rect: captionRect,
                    styleId: StyleID.caption.rawValue,
                    content: .text(captionText),
                    wrapMode: wrapModeValue
                )
            } else {
                issues.append(
                    LayoutIssue(
                        severity: .warning,
                        message: "图片 \(asset.fileName) 缺少图注",
                        category: .assets,
                        pageNumber: currentPage.number
                    )
                )
            }
            
            if let effectiveDPI = effectiveDPI(asset: asset, widthPoints: totalWidth), effectiveDPI < 220 {
                issues.append(
                    LayoutIssue(
                        severity: .warning,
                        message: "图片 \(asset.fileName) 预计印刷分辨率低于 220 DPI",
                        category: .assets,
                        pageNumber: currentPage.number
                    )
                )
            }
            
            // Add left frame
            if targetLeftPageNum == currentPage.number {
                currentPage.frames.append(leftFrame)
            } else if targetLeftPageNum < currentPage.number {
                let index = targetLeftPageNum - 1
                if index >= 0 && index < pages.count {
                    pages[index].frames.append(leftFrame)
                }
            } else {
                deferredUnderlayFrames[targetLeftPageNum, default: []].append(leftFrame)
            }

            // Add right frame
            if targetRightPageNum == currentPage.number {
                currentPage.frames.append(rightFrame)
            } else if targetRightPageNum < currentPage.number {
                let index = targetRightPageNum - 1
                if index >= 0 && index < pages.count {
                    pages[index].frames.append(rightFrame)
                }
            } else {
                deferredUnderlayFrames[targetRightPageNum, default: []].append(rightFrame)
            }

            // Add caption frame
            if let captionFrame = captionFrame {
                if targetRightPageNum == currentPage.number {
                    currentPage.frames.append(captionFrame)
                } else if targetRightPageNum < currentPage.number {
                    let index = targetRightPageNum - 1
                    if index >= 0 && index < pages.count {
                        pages[index].frames.append(captionFrame)
                    }
                } else {
                    deferredUnderlayFrames[targetRightPageNum, default: []].append(captionFrame)
                }
            }
            return
        }

        if currentAbsolutePageNumber % 2 == 1 {
            advanceToNextPage()
        }

        let bottomLimit = resolvedBottomLimit(for: currentAbsolutePageNumber)
        if cursorY + requiredHeight > bottomLimit {
            advanceToNextPage()
            advanceToNextPage()
        }

        let leftX = pageLeftMargin(for: currentAbsolutePageNumber)
        let leftWidth = pageWidth - leftX
        let leftRect = Rect(x: leftX, y: cursorY, width: leftWidth, height: desiredHeight)
        currentPage.frames.append(PageFrame(
            kind: .image,
            rect: leftRect,
            content: .spreadAsset(assetId: asset.id, isLeftHalf: true)
        ))
        
        let spreadY = cursorY
        
        advanceToNextPage()
        
        let rightWidth = pageWidth - pageRightMargin(for: currentAbsolutePageNumber)
        let rightRect = Rect(x: 0, y: spreadY, width: rightWidth, height: desiredHeight)
        currentPage.frames.append(PageFrame(
            kind: .image,
            rect: rightRect,
            content: .spreadAsset(assetId: asset.id, isLeftHalf: false)
        ))
        
        cursorY = spreadY + desiredHeight + 4
        
        if let caption = asset.caption {
            let captionText = numberedCaption(caption, number: figureCounter)
            let captionRect = Rect(x: 0, y: cursorY, width: rightWidth, height: 28)
            currentPage.frames.append(PageFrame(
                kind: .caption,
                rect: captionRect,
                styleId: StyleID.caption.rawValue,
                content: .text(captionText)
            ))
            cursorY += 34
        } else {
            issues.append(
                LayoutIssue(
                    severity: .warning,
                    message: "图片 \(asset.fileName) 缺少图注",
                    category: .assets,
                    pageNumber: currentPage.number
                )
            )
        }
        
        if let effectiveDPI = effectiveDPI(asset: asset, widthPoints: totalWidth), effectiveDPI < 220 {
            issues.append(
                LayoutIssue(
                    severity: .warning,
                    message: "图片 \(asset.fileName) 预计印刷分辨率低于 220 DPI",
                    category: .assets,
                    pageNumber: currentPage.number
                )
            )
        }
        
        snapToBaseline()
    }

    func imageWidth(for asset: Asset) -> Double {
        shouldSpanColumns(asset) ? contentWidth : columnWidth
    }

    func shouldSpanColumns(_ asset: Asset) -> Bool {
        asset.role == .hero || asset.role == .comparison
    }

    mutating func prepareWideAssetPlacement(requiredHeight: Double) {
        if currentColumn != 0 {
            advanceToNextPage()
        }

        let bottomLimit = resolvedBottomLimit(for: currentAbsolutePageNumber)
        if cursorY + requiredHeight > bottomLimit {
            advanceToNextPage()
        }

        currentColumn = 0
        if isVertical {
            cursorX = project.pageSetup.pageSize.width - pageRightMargin(for: currentAbsolutePageNumber)
        } else {
            cursorX = pageLeftMargin(for: currentAbsolutePageNumber)
        }
    }

    func imageHeight(for asset: Asset, width: Double) -> Double {
        let aspectRatio = imageAspectRatio(for: asset)
        let naturalHeight = width / aspectRatio
        let roleMultiplier: Double
        let maximumHeight: Double

        switch asset.role {
        case .hero:
            roleMultiplier = 0.90
            maximumHeight = 320
        case .diagram, .chart, .comparison:
            roleMultiplier = asset.role == .comparison ? 0.85 : 1.10
            maximumHeight = asset.role == .comparison ? 300 : 220
        case .step:
            roleMultiplier = 0.95
            maximumHeight = 190
        case .photo:
            roleMultiplier = 1.0
            maximumHeight = 200
        case .decorative:
            roleMultiplier = 0.65
            maximumHeight = 120
        case .spread:
            roleMultiplier = 0.90
            maximumHeight = 320
        }

        return max(86, min(naturalHeight * roleMultiplier, maximumHeight))
    }

    func imageAspectRatio(for asset: Asset) -> Double {
        guard asset.pixelWidth > 0, asset.pixelHeight > 0 else {
            return 1.5
        }
        return max(Double(asset.pixelWidth) / Double(asset.pixelHeight), 0.2)
    }

    func effectiveDPI(asset: Asset, widthPoints: Double) -> Double? {
        guard asset.pixelWidth > 0, widthPoints > 0 else {
            return asset.dpi
        }
        return Double(asset.pixelWidth) / (widthPoints / 72)
    }

    func numberedCaption(_ caption: String, number: Int) -> String {
        let caption = caption.trimmedForLayout
        guard !caption.hasPrefix("图") else {
            return caption
        }
        return "图\(number) \(caption)"
    }
}
