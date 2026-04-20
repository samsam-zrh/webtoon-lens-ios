import Foundation

#if canImport(CryptoKit)
import CryptoKit
#endif

public enum ImageHasher {
    public static func sha256Hex(_ data: Data) -> String {
        #if canImport(CryptoKit)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        #else
        return String(data.hashValue)
        #endif
    }
}
