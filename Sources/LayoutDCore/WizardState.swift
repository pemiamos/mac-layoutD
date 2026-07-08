import Foundation

public struct WizardState: Codable, Equatable, Sendable {
    public var currentStep: Int // 1 to 6
    public var maxUnlockedStep: Int // 1 to 6
    
    // Step 1: Reference image paths or metadata
    public var referenceImages: [String]
    
    // Step 2: Spec pack file path or data/name
    public var specPackPath: String?
    public var specPackName: String?
    
    // Step 3: Generated sample PDF path or details
    public var samplePDFPath: String?
    
    // Step 4: Frozen Style Profile path or info
    public var isStyleFrozen: Bool
    
    // Step 5: Chosen archetypes or planner configurations
    public var chosenArchetypes: [String]
    
    // Step 6: Exported IDML path
    public var exportedIDMLPath: String?

    public init(
        currentStep: Int = 1,
        maxUnlockedStep: Int = 1,
        referenceImages: [String] = [],
        specPackPath: String? = nil,
        specPackName: String? = nil,
        samplePDFPath: String? = nil,
        isStyleFrozen: Bool = false,
        chosenArchetypes: [String] = [],
        exportedIDMLPath: String? = nil
    ) {
        self.currentStep = currentStep
        self.maxUnlockedStep = maxUnlockedStep
        self.referenceImages = referenceImages
        self.specPackPath = specPackPath
        self.specPackName = specPackName
        self.samplePDFPath = samplePDFPath
        self.isStyleFrozen = isStyleFrozen
        self.chosenArchetypes = chosenArchetypes
        self.exportedIDMLPath = exportedIDMLPath
    }
}
