/* Host-side tests for crc32.c. */

#include "crc32.h"
#include "unit.h"

static crc32_t crc_of(const void *data, unsigned len)
{
    return CRC32_FINAL(crc32_update(CRC32_INIT,
                                    (const unsigned char *)data, len));
}

int main(void)
{
    static const unsigned char bytes[] = { 0x00, 0x1a, 0x80, 0xff };
    static const unsigned char zero[1] = { 0x00 };
    static const unsigned char ctrlz[1] = { 0x1a };
    static const unsigned char ff[1] = { 0xff };
    unsigned char big[1000];
    crc32_t whole, crc;
    unsigned i, split;

    crc32_init();

    /* catalogue check value and well-known vectors (zlib.crc32) */
    CHECK(crc_of("", 0) == 0x00000000UL);
    CHECK(crc_of("123456789", 9) == 0xCBF43926UL);
    CHECK(crc_of("a", 1) == 0xE8B7BE43UL);
    CHECK(crc_of("The quick brown fox jumps over the lazy dog", 43)
          == 0x414FA339UL);

    /* binary bytes, including Ctrl-Z */
    CHECK(crc_of(zero, 1) == 0xD202EF8DUL);
    CHECK(crc_of(ctrlz, 1) == 0x2F6016F7UL);
    CHECK(crc_of(ff, 1) == 0xFF000000UL);
    CHECK(crc_of(bytes, sizeof bytes) == 0x26748E7CUL);

    /* results never exceed 32 bits, even where long is wider */
    CHECK((crc_of(big, 0) & ~0xFFFFFFFFUL) == 0);

    /* incremental updates at every split give the one-shot result */
    for (i = 0; i < sizeof big; i++)
        big[i] = (unsigned char)(i * 7 + (i >> 3));
    whole = crc_of(big, sizeof big);
    CHECK((whole & ~0xFFFFFFFFUL) == 0);
    for (split = 0; split <= sizeof big; split++) {
        crc = crc32_update(CRC32_INIT, big, split);
        crc = crc32_update(crc, big + split, sizeof big - split);
        if (CRC32_FINAL(crc) != whole) {
            CHECK(CRC32_FINAL(crc) == whole);
            break;
        }
    }
    CHECK(split > sizeof big);

    /* byte-at-a-time matches */
    crc = CRC32_INIT;
    for (i = 0; i < sizeof big; i++)
        crc = crc32_update(crc, big + i, 1);
    CHECK(CRC32_FINAL(crc) == whole);

    return UNIT_DONE();
}
