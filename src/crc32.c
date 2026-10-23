#include "crc32.h"

static crc32_t table[256];

void crc32_init(void)
{
    crc32_t c;
    unsigned n, k;

    for (n = 0; n < 256; n++) {
        c = n;
        for (k = 0; k < 8; k++)
            c = (c & 1) ? 0xEDB88320UL ^ (c >> 1) : c >> 1;
        table[n] = c;
    }
}

crc32_t crc32_update(crc32_t crc, const unsigned char *buf, unsigned len)
{
    /* Index with the low byte only, so the compiler need not form a
       32-bit XOR just to throw away its upper 24 bits. */
    while (len--)
        crc = table[(unsigned char)crc ^ *buf++] ^ (crc >> 8);
    return crc;
}
