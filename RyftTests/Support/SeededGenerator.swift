import Foundation

/// SplitMix64: a deterministic generator for test noise.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// A standard normal draw (Box–Muller).
    mutating func gaussian() -> Double {
        let u = Double.random(in: Double.ulpOfOne ..< 1, using: &self)
        let v = Double.random(in: 0 ..< 1, using: &self)
        return (-2 * log(u)).squareRoot() * cos(2 * .pi * v)
    }
}
