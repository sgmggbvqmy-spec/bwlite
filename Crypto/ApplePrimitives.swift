// Everything that needs an Apple framework: PBKDF2 and AES (CommonCrypto), RSA and certificates (Security) and random
// bytes. The test harness in vwcore/ replaces this one file with a Linux version.

import Foundation
import Security   // RSA keys and certificates
import CommonCrypto   // PBKDF2 and AES

/// Everything that needs an Apple framework: PBKDF2 and AES (CommonCrypto), RSA (Security) and random bytes.
nonisolated enum VWPrim {
    static func random(_ count: Int) -> Data {
        var data = Data(count: count)
        let status = data.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!) }
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed")
        return data
    }

    static func pbkdf2(password: Data, salt: Data, iterations: Int) throws -> Data {
        var derived = Data(count: 32)
        let status = derived.withUnsafeMutableBytes { out in
            password.withUnsafeBytes { pw in
                salt.withUnsafeBytes { s in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        pw.baseAddress?.assumingMemoryBound(to: CChar.self), password.count,
                        s.baseAddress?.assumingMemoryBound(to: UInt8.self), salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), UInt32(iterations),
                        out.baseAddress?.assumingMemoryBound(to: UInt8.self), 32)
                }
            }
        }
        guard status == kCCSuccess else { throw VWError.failed("Key derivation failed (\(status)).") }
        return derived
    }

    /// AES-256-CBC with PKCS#7 padding.
    static func aesCBC(encrypt: Bool, key: UnsafeRawBufferPointer, iv: Data, input: Data) throws -> Data {
        var out = Data(count: input.count + kCCBlockSizeAES128)
        var moved = 0
        let capacity = out.count
        let status = out.withUnsafeMutableBytes { o in
            input.withUnsafeBytes { i in
                iv.withUnsafeBytes { v in
                    CCCrypt(CCOperation(encrypt ? kCCEncrypt : kCCDecrypt), CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding), key.baseAddress, key.count, v.baseAddress,
                            i.baseAddress, input.count, o.baseAddress, capacity, &moved)
                }
            }
        }
        guard status == kCCSuccess else { throw VWError.failed("Decryption failed (\(status)).") }
        return out.prefix(moved)
    }

    /// RSA-OAEP decryption with the account's private key (PKCS#8 DER). `sha256` false means SHA-1.
    static func rsaDecrypt(pkcs8: Data, ciphertext: Data, sha256: Bool) throws -> Data {
        guard let pkcs1 = pkcs1(fromPKCS8: pkcs8) else { throw VWError.failed("The account's private key can't be read.") }
        let attributes: [String: Any] = [kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
                                         kSecAttrKeyClass as String: kSecAttrKeyClassPrivate]
        guard let key = SecKeyCreateWithData(pkcs1 as CFData, attributes as CFDictionary, nil) else {
            throw VWError.failed("The account's private key can't be read.")
        }
        let algorithm: SecKeyAlgorithm = sha256 ? .rsaEncryptionOAEPSHA256 : .rsaEncryptionOAEPSHA1
        var error: Unmanaged<CFError>?
        guard let plain = SecKeyCreateDecryptedData(key, algorithm, ciphertext as CFData, &error) as Data? else {
            throw VWError.failed("An organization key can't be decrypted.")
        }
        return plain
    }

    /// PKCS#8 PrivateKeyInfo ::= SEQUENCE { version INTEGER, algorithm SEQUENCE, privateKey OCTET STRING }.
    /// The OCTET STRING holds the PKCS#1 key that Security wants.
    private static func pkcs1(fromPKCS8 der: Data) -> Data? {
        let bytes = [UInt8](der)
        var i = 0
        func header(_ tag: UInt8) -> Int? {
            guard i < bytes.count, bytes[i] == tag else { return nil }
            i += 1
            guard i < bytes.count else { return nil }
            var length = Int(bytes[i]); i += 1
            if length & 0x80 != 0 {
                let n = length & 0x7f
                guard n >= 1, n <= 4, i + n <= bytes.count else { return nil }
                length = 0
                for _ in 0..<n { length = (length << 8) | Int(bytes[i]); i += 1 }
            }
            return i + length <= bytes.count ? length : nil
        }
        guard header(0x30) != nil else { return nil }                       // PrivateKeyInfo
        guard let versionLength = header(0x02) else { return nil }          // version
        i += versionLength
        guard let algorithmLength = header(0x30) else { return nil }        // algorithm
        i += algorithmLength
        guard let keyLength = header(0x04) else { return nil }              // privateKey
        return Data(bytes[i..<(i + keyLength)])
    }
}

/// Lets URLSession accept your server's certificate when you chose a certificate file in Settings. The macOS
/// keychain is used as usual: a certificate set to "Always Trust" in Keychain Access needs nothing here.
nonisolated final class VWTrust: VWSessionDelegate, @unchecked Sendable {
    private let anchors: [SecCertificate]

    init(pemFile path: String, followRedirects: Bool = true) {
        var found: [SecCertificate] = []
        if !path.isEmpty, let data = FileManager.default.contents(atPath: path) {
            if let der = SecCertificateCreateWithData(nil, data as CFData) {
                found.append(der)   // the file is a single DER certificate
            } else if let text = String(data: data, encoding: .utf8) {
                for block in text.components(separatedBy: "-----BEGIN CERTIFICATE-----").dropFirst() {
                    guard let end = block.range(of: "-----END CERTIFICATE-----") else { continue }
                    let base64 = block[..<end.lowerBound].filter { !$0.isWhitespace }
                    if let der = Data(base64Encoded: String(base64)),
                       let cert = SecCertificateCreateWithData(nil, der as CFData) {
                        found.append(cert)
                    }
                }
            }
        }
        anchors = found
        super.init(followRedirects: followRedirects)
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge)
        async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        guard !anchors.isEmpty,
              challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else { return (.performDefaultHandling, nil) }
        SecTrustSetAnchorCertificates(trust, anchors as CFArray)
        SecTrustSetAnchorCertificatesOnly(trust, false)   // the system's own roots and your keychain settings still count
        var error: CFError?
        if SecTrustEvaluateWithError(trust, &error) { return (.useCredential, URLCredential(trust: trust)) }
        return (.performDefaultHandling, nil)
    }
}
