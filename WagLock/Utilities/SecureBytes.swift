//
//  SecureBytes.swift
//  WagLock
//
//  Reference-semantics container for sensitive bytes
//  Data/Array are copy-on-write (COW) value types: calling
//  withUnsafeMutableBytes on a shared value copies the buffer first, so only the copy is zeroed
//  and the original plaintext stays in memory. This class owns the bytes exclusively and never
//  exposes the underlying storage, so zeroing happens on the real buffer.
//

import Foundation

/// Holds sensitive bytes such as the session password; zeroed in place when replaced or released
final class SecureBytes {

    private var storage: [UInt8]

    init(_ string: String) {
        self.storage = Array(string.utf8)
    }

    /// Read as a String (callers should do this only when passing it to an encryption API)
    var string: String? {
        String(bytes: storage, encoding: .utf8)
    }

    var isEmpty: Bool {
        storage.isEmpty
    }

    /// Zero in place. storage is never exposed and has a single reference, so no COW copy is triggered;
    /// memset_s keeps the compiler from optimizing the wipe away
    func wipe() {
        storage.withUnsafeMutableBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress, buffer.count > 0 else { return }
            _ = memset_s(baseAddress, buffer.count, 0, buffer.count)
        }
    }

    deinit {
        wipe()
    }
}
