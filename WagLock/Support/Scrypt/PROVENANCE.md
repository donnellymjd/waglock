# scrypt source provenance

The listed source files are copied verbatim from Tarsnap/scrypt commit `cbdef576b8d4640e86b208fa3f063d4ec449110a`. Original paths are `lib/crypto/crypto_scrypt-ref.c`, `lib-platform/crypto/crypto_scrypt.h`, `libcperciva/alg/sha256.h`, `libcperciva/util/{sysendian.h,insecure_memzero.h,insecure_memzero.c}` and `COPYRIGHT`. SHA-256 values are recorded in PROVENANCE.json. Original notices are retained. The full upstream BSD-2-Clause terms are in COPYRIGHT.txt and reproduced in the app's Open Source Notices.

`age_scrypt.c` and `age_scrypt.h` are new WagLock adapter files under the repository's license. They provide the reference core's PBKDF2-SHA256 hook using Apple CommonCrypto, propagate derivation failures, and reject parameters exceeding the declared memory/length bounds. The original Salsa20/8/ROMix core is unchanged. Only this interface is included by the Swift bridge; no Cryptomator code or third-party age implementation is linked to the app. C is built with optimization enabled for practical memory-hard derivation performance. The Swift call serializes KDFs to avoid parallel 256 MiB allocations.

Production age password exports use scrypt N=262144, r=8, p=1 and a fresh salt. Validation includes RFC 7914 and independent official age CLI recovery. This is not an independent audit, FIPS certification or claim of complete memory erasure.
