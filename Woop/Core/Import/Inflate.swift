import Foundation

/// Raw DEFLATE decoder (RFC 1951), pure Swift. Used to open the WHOOP export .zip on the phone
/// without unzipping it first, and testable on any platform.
enum Inflate {
    enum Failure: Error, Equatable {
        case truncated
        case invalidBlockType
        case invalidStoredLength
        case invalidCode
        case invalidDistance
        case badCodeLengths
        case tooLarge
    }

    /// Decode a raw DEFLATE stream. Returns the output and the number of input bytes consumed.
    static func inflate(_ input: [UInt8], expectedSize: Int? = nil, limit: Int = 600 << 20) throws -> (output: [UInt8], consumed: Int) {
        var s = State(input: input, limit: limit)
        if let n = expectedSize, n > 0 { s.out.reserveCapacity(min(n, limit)) }
        var last = false
        while !last {
            last = try s.bits(1) == 1
            switch try s.bits(2) {
            case 0: try s.stored()
            case 1: try s.codes(Tables.fixedLit, Tables.fixedDist)
            case 2:
                let (lit, dist) = try s.dynamicTables()
                try s.codes(lit, dist)
            default: throw Failure.invalidBlockType
            }
        }
        // Whole bytes still buffered were read ahead and not consumed.
        return (s.out, s.pos - s.bitCount / 8)
    }

    // MARK: - Huffman tables

    struct Huffman {
        /// Indexed by the next `maxLen` stream bits: (symbol << 4) | code length; 0 = no code.
        var table: [UInt16]
        var maxLen: Int

        init(lengths: [UInt8]) throws {
            let maxLen = Int(lengths.max() ?? 0)
            self.maxLen = maxLen
            guard maxLen > 0 else {
                table = []
                return
            }
            var count = [Int](repeating: 0, count: 16)
            for l in lengths { count[Int(l)] += 1 }
            count[0] = 0
            // Reject over-subscribed sets (incomplete ones are legal).
            var left = 1
            for len in 1...15 {
                left <<= 1
                left -= count[len]
                if left < 0 { throw Failure.badCodeLengths }
            }
            var next = [Int](repeating: 0, count: 16)
            var code = 0
            for len in 1...15 {
                code = (code + count[len - 1]) << 1
                next[len] = code
            }
            var table = [UInt16](repeating: 0, count: 1 << maxLen)
            for (sym, l8) in lengths.enumerated() where l8 > 0 {
                let len = Int(l8)
                let c = next[len]
                next[len] += 1
                // Codes are stored MSB-first; the stream is read LSB-first.
                var rev = 0
                for i in 0..<len where c & (1 << i) != 0 { rev |= 1 << (len - 1 - i) }
                let entry = UInt16(sym << 4 | len)
                var fill = rev
                while fill < table.count {
                    table[fill] = entry
                    fill += 1 << len
                }
            }
            self.table = table
        }
    }

    enum Tables {
        static let lengthBase: [Int] = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258]
        static let lengthExtra: [Int] = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0]
        static let distBase: [Int] = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073,
                                      4097, 6145, 8193, 12289, 16385, 24577]
        static let distExtra: [Int] = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13]
        static let codeLengthOrder: [Int] = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]

        static let fixedLit: Huffman = {
            var l = [UInt8](repeating: 8, count: 288)
            for i in 144..<256 { l[i] = 9 }
            for i in 256..<280 { l[i] = 7 }
            return try! Huffman(lengths: l)
        }()
        static let fixedDist: Huffman = try! Huffman(lengths: [UInt8](repeating: 5, count: 30))
    }

    // MARK: - Decoder state

    struct State {
        let input: [UInt8]
        let limit: Int
        var pos = 0
        var bitBuf: UInt64 = 0
        var bitCount = 0
        var out: [UInt8] = []

        init(input: [UInt8], limit: Int) {
            self.input = input
            self.limit = limit
        }

        /// Top the bit buffer up to at least `n` bits when input allows (never throws).
        @inline(__always) mutating func fill(_ n: Int) {
            while bitCount < n && pos < input.count {
                bitBuf |= UInt64(input[pos]) << UInt64(bitCount)
                pos += 1
                bitCount += 8
            }
        }

        @inline(__always) mutating func bits(_ n: Int) throws -> Int {
            if n == 0 { return 0 }
            fill(n)
            guard bitCount >= n else { throw Failure.truncated }
            let v = Int(bitBuf & ((1 << UInt64(n)) - 1))
            bitBuf >>= UInt64(n)
            bitCount -= n
            return v
        }

        @inline(__always) mutating func decode(_ h: Huffman) throws -> Int {
            guard h.maxLen > 0 else { throw Failure.invalidCode }
            fill(h.maxLen)
            let e = h.table[Int(bitBuf & ((1 << UInt64(h.maxLen)) - 1))]
            let len = Int(e & 15)
            guard len > 0 else { throw Failure.invalidCode }
            guard len <= bitCount else { throw Failure.truncated }
            bitBuf >>= UInt64(len)
            bitCount -= len
            return Int(e >> 4)
        }

        mutating func stored() throws {
            // Drop to the byte boundary, then give back the whole bytes read ahead.
            let drop = bitCount & 7
            bitBuf >>= UInt64(drop)
            bitCount -= drop
            pos -= bitCount / 8
            bitBuf = 0
            bitCount = 0
            guard pos + 4 <= input.count else { throw Failure.truncated }
            let len = Int(input[pos]) | Int(input[pos + 1]) << 8
            let nlen = Int(input[pos + 2]) | Int(input[pos + 3]) << 8
            guard len == (~nlen & 0xFFFF) else { throw Failure.invalidStoredLength }
            pos += 4
            guard pos + len <= input.count else { throw Failure.truncated }
            guard out.count + len <= limit else { throw Failure.tooLarge }
            out.append(contentsOf: input[pos..<(pos + len)])
            pos += len
        }

        mutating func dynamicTables() throws -> (Huffman, Huffman) {
            let nlen = try bits(5) + 257
            let ndist = try bits(5) + 1
            let ncode = try bits(4) + 4
            guard nlen <= 286, ndist <= 30 else { throw Failure.badCodeLengths }
            var cl = [UInt8](repeating: 0, count: 19)
            for i in 0..<ncode { cl[Tables.codeLengthOrder[i]] = UInt8(try bits(3)) }
            let clh = try Huffman(lengths: cl)
            var lengths = [UInt8]()
            lengths.reserveCapacity(nlen + ndist)
            while lengths.count < nlen + ndist {
                let sym = try decode(clh)
                switch sym {
                case 0...15:
                    lengths.append(UInt8(sym))
                case 16:
                    guard let prev = lengths.last else { throw Failure.badCodeLengths }
                    let n = 3 + (try bits(2))
                    lengths.append(contentsOf: repeatElement(prev, count: n))
                case 17:
                    lengths.append(contentsOf: repeatElement(0, count: 3 + (try bits(3))))
                default:
                    lengths.append(contentsOf: repeatElement(0, count: 11 + (try bits(7))))
                }
            }
            guard lengths.count == nlen + ndist, lengths[256] != 0 else { throw Failure.badCodeLengths }
            let lit = try Huffman(lengths: Array(lengths[0..<nlen]))
            let dist = try Huffman(lengths: Array(lengths[nlen..<(nlen + ndist)]))
            return (lit, dist)
        }

        mutating func codes(_ lit: Huffman, _ dist: Huffman) throws {
            while true {
                let sym = try decode(lit)
                if sym < 256 {
                    out.append(UInt8(sym))
                    if out.count > limit { throw Failure.tooLarge }
                    continue
                }
                if sym == 256 { return }
                let li = sym - 257
                guard li < Tables.lengthBase.count else { throw Failure.invalidCode }
                let length = Tables.lengthBase[li] + (try bits(Tables.lengthExtra[li]))
                let di = try decode(dist)
                guard di < Tables.distBase.count else { throw Failure.invalidDistance }
                let distance = Tables.distBase[di] + (try bits(Tables.distExtra[di]))
                guard distance <= out.count else { throw Failure.invalidDistance }
                guard out.count + length <= limit else { throw Failure.tooLarge }
                var from = out.count - distance
                for _ in 0..<length {
                    out.append(out[from])
                    from += 1
                }
            }
        }
    }
}
