// Argon2id in plain Swift (the master password to key function the Bitwarden apps use besides PBKDF2).

import Foundation

/// Argon2id (RFC 9106, version 0x13) in plain Swift, because the system has none. Bitwarden's defaults are
/// 3 passes, 64 MiB and 4 lanes. Slow in a Debug build, quick in a Release build.
nonisolated enum Argon2id {
    private static func le32(_ x: Int) -> [UInt8] {
        [UInt8(truncatingIfNeeded: x), UInt8(truncatingIfNeeded: x >> 8),
         UInt8(truncatingIfNeeded: x >> 16), UInt8(truncatingIfNeeded: x >> 24)]
    }

    /// H' of the RFC: Blake2b stretched to any output length.
    private static func variableHash(_ x: [UInt8], _ length: Int) -> [UInt8] {
        if length <= 64 { return Blake2b.hash(le32(length) + x, outLength: length) }
        let r = (length + 31) / 32 - 2
        var v = Blake2b.hash(le32(length) + x, outLength: 64)
        var out = Array(v[0..<32])
        if r >= 2 {
            for _ in 2...r {
                v = Blake2b.hash(v, outLength: 64)
                out += v[0..<32]
            }
        }
        out += Blake2b.hash(v, outLength: length - 32 * r)
        return out
    }

    @inline(__always) private static func rotr(_ x: UInt64, _ n: UInt64) -> UInt64 { (x >> n) | (x << (64 - n)) }

    /// x + y + 2 * lo32(x) * lo32(y), the multiplication that makes Argon2 hard on GPUs.
    @inline(__always) private static func fBlaMka(_ x: UInt64, _ y: UInt64) -> UInt64 {
        x &+ y &+ 2 &* (x & 0xFFFF_FFFF) &* (y & 0xFFFF_FFFF)
    }

    @inline(__always)
    private static func g(_ v: UnsafeMutablePointer<UInt64>, _ a: Int, _ b: Int, _ c: Int, _ d: Int) {
        v[a] = fBlaMka(v[a], v[b]); v[d] = rotr(v[d] ^ v[a], 32)
        v[c] = fBlaMka(v[c], v[d]); v[b] = rotr(v[b] ^ v[c], 24)
        v[a] = fBlaMka(v[a], v[b]); v[d] = rotr(v[d] ^ v[a], 16)
        v[c] = fBlaMka(v[c], v[d]); v[b] = rotr(v[b] ^ v[c], 63)
    }

    @inline(__always)
    private static func permute(_ v: UnsafeMutablePointer<UInt64>,
                                _ i0: Int, _ i1: Int, _ i2: Int, _ i3: Int, _ i4: Int, _ i5: Int, _ i6: Int, _ i7: Int,
                                _ i8: Int, _ i9: Int, _ i10: Int, _ i11: Int, _ i12: Int, _ i13: Int, _ i14: Int, _ i15: Int) {
        g(v, i0, i4, i8, i12); g(v, i1, i5, i9, i13); g(v, i2, i6, i10, i14); g(v, i3, i7, i11, i15)
        g(v, i0, i5, i10, i15); g(v, i1, i6, i11, i12); g(v, i2, i7, i8, i13); g(v, i3, i4, i9, i14)
    }

    /// out = P(prev xor ref) xor prev xor ref   (and xor the old `out` too when `xorOut` is set, for passes after the first).
    private static func fillBlock(_ prev: UnsafePointer<UInt64>, _ ref: UnsafePointer<UInt64>,
                                  _ out: UnsafeMutablePointer<UInt64>, xorOut: Bool,
                                  _ r: UnsafeMutablePointer<UInt64>, _ z: UnsafeMutablePointer<UInt64>) {
        for i in 0..<128 {
            let x = prev[i] ^ ref[i]
            r[i] = x
            z[i] = x
        }
        for i in 0..<8 {
            let b = 16 * i
            permute(z, b, b + 1, b + 2, b + 3, b + 4, b + 5, b + 6, b + 7, b + 8, b + 9, b + 10, b + 11, b + 12, b + 13, b + 14, b + 15)
        }
        for i in 0..<8 {
            let b = 2 * i
            permute(z, b, b + 1, b + 16, b + 17, b + 32, b + 33, b + 48, b + 49,
                    b + 64, b + 65, b + 80, b + 81, b + 96, b + 97, b + 112, b + 113)
        }
        if xorOut {
            for i in 0..<128 { out[i] = out[i] ^ r[i] ^ z[i] }
        } else {
            for i in 0..<128 { out[i] = r[i] ^ z[i] }
        }
    }

    static func hash(password: Data, salt: Data, iterations t: Int, memoryKiB m: Int, parallelism p: Int, length: Int) -> Data {
        let syncPoints = 4
        let blockCount = 4 * p * (m / (4 * p))
        let laneLength = blockCount / p
        let segmentLength = laneLength / syncPoints

        var seed = [UInt8]()
        seed += le32(p) + le32(length) + le32(m) + le32(t) + le32(0x13) + le32(2)
        seed += le32(password.count) + [UInt8](password) + le32(salt.count) + [UInt8](salt) + le32(0) + le32(0)
        let h0 = Blake2b.hash(seed, outLength: 64)

        let mem = UnsafeMutablePointer<UInt64>.allocate(capacity: blockCount * 128)
        mem.initialize(repeating: 0, count: blockCount * 128)
        let r = UnsafeMutablePointer<UInt64>.allocate(capacity: 128)
        let z = UnsafeMutablePointer<UInt64>.allocate(capacity: 128)
        let zero = UnsafeMutablePointer<UInt64>.allocate(capacity: 128)
        let input = UnsafeMutablePointer<UInt64>.allocate(capacity: 128)
        let address = UnsafeMutablePointer<UInt64>.allocate(capacity: 128)
        let temp = UnsafeMutablePointer<UInt64>.allocate(capacity: 128)
        for buffer in [r, z, zero, input, address, temp] { buffer.initialize(repeating: 0, count: 128) }
        defer {
            mem.deallocate(); r.deallocate(); z.deallocate(); zero.deallocate()
            input.deallocate(); address.deallocate(); temp.deallocate()
        }

        // The first two blocks of every lane come from the seed.
        for lane in 0..<p {
            for j in 0..<2 {
                let bytes = variableHash(h0 + le32(j) + le32(lane), 1024)
                let base = (lane * laneLength + j) * 128
                for k in 0..<128 {
                    var word: UInt64 = 0
                    for b in 0..<8 { word |= UInt64(bytes[k * 8 + b]) << UInt64(8 * b) }
                    mem[base + k] = word
                }
            }
        }

        for pass in 0..<t {
            for slice in 0..<syncPoints {
                let dataIndependent = pass == 0 && slice < 2
                for lane in 0..<p {
                    let start = (pass == 0 && slice == 0) ? 2 : 0
                    if dataIndependent {
                        input.update(repeating: 0, count: 128)
                        input[0] = UInt64(pass); input[1] = UInt64(lane); input[2] = UInt64(slice)
                        input[3] = UInt64(blockCount); input[4] = UInt64(t); input[5] = 2
                    }
                    func nextAddresses() {
                        input[6] &+= 1
                        fillBlock(zero, input, temp, xorOut: false, r, z)
                        fillBlock(zero, temp, address, xorOut: false, r, z)
                    }
                    if dataIndependent && start != 0 { nextAddresses() }

                    var current = lane * laneLength + slice * segmentLength + start
                    for i in start..<segmentLength {
                        let previous = (i > 0 || slice > 0) ? current - 1 : current + laneLength - 1
                        let random: UInt64
                        if dataIndependent {
                            if i % 128 == 0 { nextAddresses() }
                            random = address[i % 128]
                        } else {
                            random = mem[previous * 128]
                        }
                        let j1 = random & 0xFFFF_FFFF
                        let j2 = random >> 32
                        let refLane = (pass == 0 && slice == 0) ? lane : Int(j2 % UInt64(p))
                        let sameLane = refLane == lane
                        let area: Int
                        if pass == 0 {
                            if slice == 0 { area = i - 1 }
                            else if sameLane { area = slice * segmentLength + i - 1 }
                            else { area = slice * segmentLength + (i == 0 ? -1 : 0) }
                        } else {
                            if sameLane { area = laneLength - segmentLength + i - 1 }
                            else { area = laneLength - segmentLength + (i == 0 ? -1 : 0) }
                        }
                        let relative = (j1 &* j1) >> 32
                        let position = area - 1 - Int((UInt64(area) &* relative) >> 32)
                        let startPosition = pass == 0 ? 0 : (slice == syncPoints - 1 ? 0 : (slice + 1) * segmentLength)
                        let reference = refLane * laneLength + (startPosition + position) % laneLength
                        fillBlock(mem + previous * 128, mem + reference * 128, mem + current * 128,
                                  xorOut: pass != 0, r, z)
                        current += 1
                    }
                }
            }
        }

        // The tag is the xor of every lane's last block, stretched to the wanted length.
        var final = [UInt64](repeating: 0, count: 128)
        for lane in 0..<p {
            let base = (lane * laneLength + laneLength - 1) * 128
            for k in 0..<128 { final[k] ^= mem[base + k] }
        }
        var bytes = [UInt8]()
        bytes.reserveCapacity(1024)
        for word in final {
            for b in 0..<8 { bytes.append(UInt8(truncatingIfNeeded: word >> UInt64(8 * b))) }
        }
        return Data(variableHash(bytes, length))
    }
}
