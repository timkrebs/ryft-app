import Foundation
import Testing
@testable import Ryft

/// Seeded random mutations of the fixtures (design §11): the parser returns or throws `ImportError`, never anything
/// else and never a crash; its work stays linear (counted, not timed); the same bytes give the same bundle. Each case
/// prints its seed first, so a crash names the input that caused it.
@Suite("Import fuzz")
struct ImportFuzzTests {
    static let fixtures = ["ap-plans", "ap-workouts", "ap-workouts-de", "ap-workouts-lbs", "ap-workouts-edge", "header-row"]
    static let seedsPerFixture: UInt64 = 500

    @Test(arguments: fixtures)
    func mutatedFilesNeverCrash(_ name: String) throws {
        let base = try ImportFixture.data(name)
        let salt = UInt64(Self.fixtures.firstIndex(of: name) ?? 0) << 32
        var tally = Tally()
        for seed in salt..<(salt + Self.seedsPerFixture) {
            print("ImportFuzz \(name) seed \(seed)")
            var rng = SplitMix64(seed: seed)
            let data = FuzzMutator.mutate(base, using: &rng)
            Self.check(data, label: "\(name) seed \(seed)", tally: &tally)
        }
        #expect(tally.parsed + tally.refused == Int(Self.seedsPerFixture))
        #expect(tally.parsed > 0)
    }

    @Test func theMutatorIsDeterministic() throws {
        let base = try ImportFixture.data("ap-workouts")
        var first = SplitMix64(seed: 42)
        var second = SplitMix64(seed: 42)
        #expect(FuzzMutator.mutate(base, using: &first) == FuzzMutator.mutate(base, using: &second))
        var rng = SplitMix64(seed: 0)
        #expect(rng.next() == 0xE220_A839_7B1D_CDAF) // the reference SplitMix64 sequence
    }

    struct Tally {
        var parsed = 0
        var refused = 0
    }

    private static func check(_ data: Data, label: String, tally: inout Tally) {
        let format = AlphaProgressionFormat()
        _ = format.detect(data)
        let limits = ImportLimits.standard
        var stats = ParseStats()
        let bundle: ImportBundle
        do {
            bundle = try format.parse(data, limits: limits, stats: &stats)
        } catch is ImportError {
            tally.refused += 1
            return
        } catch {
            Issue.record("\(label): threw \(error)")
            return
        }
        tally.parsed += 1
        let lines = bundle.lineCount
        if stats.steps > 4 * lines + 16 {
            Issue.record("\(label): \(stats.steps) steps for \(lines) lines")
        }
        let warningLines = bundle.warnings.map(\.at.line)
        if warningLines != warningLines.sorted() || !warningLines.allSatisfy({ $0 >= 1 && $0 <= lines }) {
            Issue.record("\(label): warning lines out of order or range")
        }
        if bundle.warnings.count > limits.maxWarnings || bundle.warnings.contains(where: { $0.at.file != 0 }) {
            Issue.record("\(label): warnings over the cap or in another file")
        }
        // A session header has at least two fields, so it needs a `;`.
        let linesWithSeparator = data.split(whereSeparator: { $0 == 0x0A || $0 == 0x0D }).filter { $0.contains(0x3B) }.count
        if bundle.sessions.count > linesWithSeparator || bundle.plans.count > lines {
            Issue.record("\(label): \(bundle.sessions.count) sessions from \(linesWithSeparator) lines with a separator")
        }
        let sources = bundle.sessions.map(\.source.line) + bundle.plans.map(\.source.line)
        if !sources.allSatisfy({ $0 >= 1 && $0 <= lines }) {
            Issue.record("\(label): a source line out of range")
        }
        for session in bundle.sessions {
            if session.exercises.count > limits.maxExercisesPerBlock {
                Issue.record("\(label): too many exercises")
            }
            for exercise in session.exercises {
                let ordinals = exercise.sets.map(\.ordinal)
                if exercise.sets.count > limits.maxSetsPerExercise || ordinals != ordinals.sorted() || Set(ordinals).count != ordinals.count {
                    Issue.record("\(label): set ordinals not increasing or over the cap")
                }
            }
        }
        let again = try? format.parse(data, limits: limits)
        if again != bundle {
            Issue.record("\(label): the same bytes gave another bundle")
        }
    }
}

/// The reference SplitMix64 (Steele, Lea, Flood 2014): small, seedable and the same on every platform.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// 1–8 random mutations per case: delete, duplicate, swap or join lines; truncate; insert separators, quotes, `·`,
/// CR, NUL, invalid UTF-8 or U+FFFD; put a bad number in place of a number; flip the BOM or the line ends; add a
/// 64 KiB line or a 4 000-byte line of separators and quotes; drop all blank lines.
enum FuzzMutator {
    private static let bom: [UInt8] = [0xEF, 0xBB, 0xBF]
    private static let inserts: [[UInt8]] = [[0x3B], [0x22], [0xC2, 0xB7], [0x0D], [0x00], [0xFF], [0xC3], [0xEF, 0xBF, 0xBD],
                                             [0xE2, 0x80], [0x20, 0xC2, 0xB7, 0x20]]
    private static let numbers: [String] = ["9999999999999", "1e309", "nan", "-0", "+", ",,", "\u{0663}\u{0660}", "-",
                                            "1.234,5", "inf", "", "0", "+-1"]
    private static let noise: [UInt8] = [0x3B, 0x22, 0x31, 0x20, 0x2E, 0x2D, 0x2B]

    static func mutate(_ data: Data, using rng: inout SplitMix64) -> Data {
        var bytes = [UInt8](data)
        for _ in 0..<Int.random(in: 1...8, using: &rng) {
            bytes = apply(Int.random(in: 0..<12, using: &rng), to: bytes, using: &rng)
        }
        return Data(bytes)
    }

    private static func apply(_ kind: Int, to bytes: [UInt8], using rng: inout SplitMix64) -> [UInt8] {
        var lines = bytes.split(separator: 0x0A, omittingEmptySubsequences: false).map(Array.init)
        switch kind {
        case 0: // delete a line
            guard !lines.isEmpty else { return bytes }
            lines.remove(at: Int.random(in: 0..<lines.count, using: &rng))
        case 1: // duplicate a line
            guard !lines.isEmpty else { return bytes }
            let index = Int.random(in: 0..<lines.count, using: &rng)
            lines.insert(lines[index], at: index)
        case 2: // swap two lines
            guard lines.count >= 2 else { return bytes }
            lines.swapAt(Int.random(in: 0..<lines.count, using: &rng), Int.random(in: 0..<lines.count, using: &rng))
        case 3: // join two lines
            guard lines.count >= 2 else { return bytes }
            let index = Int.random(in: 0..<(lines.count - 1), using: &rng)
            lines[index] += lines[index + 1]
            lines.remove(at: index + 1)
        case 4: // truncate at a random byte
            guard !bytes.isEmpty else { return bytes }
            return Array(bytes.prefix(Int.random(in: 0..<bytes.count, using: &rng)))
        case 5: // insert a separator, a quote, `·`, CR, NUL, invalid UTF-8 or U+FFFD
            var out = bytes
            let insert = inserts[Int.random(in: 0..<inserts.count, using: &rng)]
            out.insert(contentsOf: insert, at: Int.random(in: 0...out.count, using: &rng))
            return out
        case 6: // a bad number in place of a number
            return replaceNumber(in: bytes, using: &rng)
        case 7: // flip the BOM
            return bytes.starts(with: bom) ? Array(bytes.dropFirst(3)) : bom + bytes
        case 8: // flip the line ends
            if bytes.contains(0x0D) { return bytes.filter { $0 != 0x0D } }
            lines = lines.map { $0 + [0x0D] }
        case 9: // a 64 KiB line
            lines.insert([UInt8](repeating: 0x41, count: 64 << 10), at: Int.random(in: 0...lines.count, using: &rng))
        case 10: // a long line of separators, quotes and digits, under the line cap
            let line = (0..<4_000).map { _ in noise[Int.random(in: 0..<noise.count, using: &rng)] }
            lines.insert(line, at: Int.random(in: 0...lines.count, using: &rng))
        default: // drop all blank lines
            lines.removeAll { $0.isEmpty || $0 == [0x0D] }
        }
        return Array(lines.joined(separator: [0x0A]))
    }

    private static func replaceNumber(in bytes: [UInt8], using rng: inout SplitMix64) -> [UInt8] {
        var runs: [Range<Int>] = []
        var index = 0
        while index < bytes.count {
            guard (0x30...0x39).contains(bytes[index]) else {
                index += 1
                continue
            }
            let start = index
            while index < bytes.count, (0x30...0x39).contains(bytes[index]) { index += 1 }
            runs.append(start..<index)
        }
        guard !runs.isEmpty else { return bytes }
        var out = bytes
        let run = runs[Int.random(in: 0..<runs.count, using: &rng)]
        out.replaceSubrange(run, with: Array(numbers[Int.random(in: 0..<numbers.count, using: &rng)].utf8))
        return out
    }
}
