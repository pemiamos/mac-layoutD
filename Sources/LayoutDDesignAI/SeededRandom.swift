import Foundation

public struct SeededRandom: Sendable {
    private var state: UInt64
    
    public init(seed: UInt64) {
        // Prevent seed being exactly 0 (which can cause SplitMix64 to generate repeating zeros for some steps)
        self.state = seed == 0 ? 0x9e3779b97f4a7c15 : seed
    }
    
    public mutating func next() -> UInt64 {
        state = state &+ 0x9e3779b97f4a7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
        z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
        return z ^ (z >> 31)
    }
    
    public mutating func nextDouble() -> Double {
        return Double(next() & 0xFFFFFFFF) / Double(0xFFFFFFFF)
    }
}
