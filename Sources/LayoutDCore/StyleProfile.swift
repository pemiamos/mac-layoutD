import Foundation

public struct StyleProfile: Codable, Equatable, Sendable {
    public var specPackJSON: String
    public var samplePDFPath: String
    public var unsupportedFields: [String]
    public var supportedTokensCount: Int
    public var styles: StyleLibrary
    public var timestamp: Date

    public init(
        specPackJSON: String,
        samplePDFPath: String,
        unsupportedFields: [String],
        supportedTokensCount: Int,
        styles: StyleLibrary,
        timestamp: Date = Date()
    ) {
        self.specPackJSON = specPackJSON
        self.samplePDFPath = samplePDFPath
        self.unsupportedFields = unsupportedFields
        self.supportedTokensCount = supportedTokensCount
        self.styles = styles
        self.timestamp = timestamp
    }
}

public struct StyleReport: Codable, Equatable, Sendable {
    public var tokenCoverage: Double          // e.g. 0.85 (85%)
    public var motifsChecklist: [String: Bool] // Motif name -> present in doc
    public var layoutRepeatCount: Int         // Maximum consecutive identical layout plan strategies
    public var repeatViolationCount: Int      // How many templates repeat more than allowed
    public var densityReport: [PageDensity]   // Density info per page
    public var overlapsCheck: Bool            // True if overlaps exist
    public var overflowsCheck: Bool           // True if overflows exist

    public init(
        tokenCoverage: Double = 0.0,
        motifsChecklist: [String: Bool] = [:],
        layoutRepeatCount: Int = 0,
        repeatViolationCount: Int = 0,
        densityReport: [PageDensity] = [],
        overlapsCheck: Bool = false,
        overflowsCheck: Bool = false
    ) {
        self.tokenCoverage = tokenCoverage
        self.motifsChecklist = motifsChecklist
        self.layoutRepeatCount = layoutRepeatCount
        self.repeatViolationCount = repeatViolationCount
        self.densityReport = densityReport
        self.overlapsCheck = overlapsCheck
        self.overflowsCheck = overflowsCheck
    }
}

public struct PageDensity: Codable, Equatable, Sendable {
    public var pageNumber: Int
    public var textDensity: Double            // Area ratio of text frames (0.0 to 1.0)
    public var imageDensity: Double           // Area ratio of image frames (0.0 to 1.0)
    public var layoutStrategy: String

    public init(pageNumber: Int, textDensity: Double, imageDensity: Double, layoutStrategy: String) {
        self.pageNumber = pageNumber
        self.textDensity = textDensity
        self.imageDensity = imageDensity
        self.layoutStrategy = layoutStrategy
    }
}
