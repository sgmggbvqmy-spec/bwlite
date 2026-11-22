// Keys that are overwritten with zeros when they are let go.

import Foundation

/// Overwriting memory that held a secret.
nonisolated enum VWMemory {
    /// Writes zeros that the compiler may not drop as a "dead store" (it would, for a plain loop or `memset`,
    /// when the memory is freed right after).
    static func wipe(_ pointer: UnsafeMutableRawPointer, count: Int) {
        guard count > 0 else { return }
        #if canImport(Darwin)
        _ = memset_s(pointer, count, 0, count)
        #else
        explicit_bzero(pointer, count)
        #endif
    }
}

extension Data {
    /// Overwrites the bytes with zeros and empties the Data. This reaches the real bytes only while nothing else
    /// shares them (a `Data` is copied on write), so it is used on temporary buffers that nobody else holds.
    nonisolated mutating func wipe() {
        withUnsafeMutableBytes { if let start = $0.baseAddress { VWMemory.wipe(start, count: $0.count) } }
        self = Data()
    }
}

/// A user or organization key: 32 bytes for AES-256 and 32 for HMAC-SHA256.
///
/// The bytes live in one buffer that is overwritten by `wipe()` (locking, logging out) and when the key is
/// released. Encrypting and decrypting read them in place; only `enc`, `mac` and `combined` make a copy.
nonisolated final class VWKey: @unchecked Sendable {
    private let bytes: UnsafeMutableRawPointer

    init(enc: Data, mac: Data) {
        precondition(enc.count == 32 && mac.count == 32, "A key is 32 bytes for encryption and 32 for the MAC")
        bytes = UnsafeMutableRawPointer.allocate(byteCount: 64, alignment: 16)
        enc.copyBytes(to: bytes.assumingMemoryBound(to: UInt8.self), count: 32)
        mac.copyBytes(to: (bytes + 32).assumingMemoryBound(to: UInt8.self), count: 32)
    }

    /// From the 64 bytes Bitwarden stores (encryption key first).
    convenience init?(combined: Data) {
        guard combined.count == 64 else { return nil }
        self.init(enc: combined.prefix(32), mac: combined.suffix(32))
    }

    deinit {
        VWMemory.wipe(bytes, count: 64)
        bytes.deallocate()
    }

    /// Overwrites the key with zeros. Whatever still holds this key can no longer decrypt anything with it.
    func wipe() { VWMemory.wipe(bytes, count: 64) }

    func withEnc<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
        try body(UnsafeRawBufferPointer(start: bytes, count: 32))
    }

    func withMac<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
        try body(UnsafeRawBufferPointer(start: bytes + 32, count: 32))
    }

    /// Copies, for the few places that need the bytes themselves (the key kept for Touch ID, a key being wrapped).
    var enc: Data { Data(bytes: bytes, count: 32) }
    var mac: Data { Data(bytes: bytes + 32, count: 32) }
    var combined: Data { Data(bytes: bytes, count: 64) }
}
