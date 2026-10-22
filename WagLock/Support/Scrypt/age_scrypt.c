// WagLock adapter: original Tarsnap scrypt core, Apple CommonCrypto PBKDF2.
// Upstream files and copyright are retained verbatim. See PROVENANCE.md.
#include <CommonCrypto/CommonKeyDerivation.h>
#include <CommonCrypto/CommonCryptoError.h>
#include <errno.h>
#include <limits.h>
#include <string.h>
#include "age_scrypt.h"
#include "crypto_scrypt.h"
#include "insecure_memzero.h"
#include "sha256.h"
static _Thread_local int pbkdf_failed;
void PBKDF2_SHA256(const uint8_t *p, size_t pl, const uint8_t *s, size_t sl,
    uint64_t c, uint8_t *out, size_t len) {
    if (c != 1 || CCKeyDerivationPBKDF(kCCPBKDF2, (const char *)p, pl,
        s, sl, kCCPRFHmacAlgSHA256, 1, out, len) != kCCSuccess) {
        pbkdf_failed = 1;
        memset(out, 0, len);
    }
}
int waglock_age_scrypt(const uint8_t *p, size_t pl, const uint8_t *s, size_t sl,
    uint64_t n, uint32_t r, uint32_t parallel, uint8_t *out, size_t len) {
    if (pl > 16384 || sl > 1024 || n < 2 || n > (1ULL << 18) ||
        !r || r > 8 || !parallel || parallel > 16 || !len || len > 64 ||
        (n & (n - 1)) || (!p && pl) || (!s && sl) || !out) {
        errno = EINVAL; return -1;
    }
    pbkdf_failed = 0;
    int result = crypto_scrypt(p, pl, s, sl, n, r, parallel, out, len);
    if (result || pbkdf_failed) {
        insecure_memzero(out, len); return -1;
    }
    return 0;
}
