#ifndef CRC32_H
#define CRC32_H

/*
 * CRC-32/ISO-HDLC (ZIP, Ethernet): reflected polynomial 0xEDB88320,
 * initial value and final XOR 0xFFFFFFFF.  unsigned long is at least
 * 32 bits everywhere; values never exceed 32 bits.
 */

typedef unsigned long crc32_t;

#define CRC32_INIT  0xFFFFFFFFUL
#define CRC32_FINAL(crc)  ((crc) ^ 0xFFFFFFFFUL)

/* Build the lookup table.  Call once before crc32_update. */
void crc32_init(void);

/* Feed len bytes into a running CRC (start from CRC32_INIT). */
crc32_t crc32_update(crc32_t crc, const unsigned char *buf, unsigned len);

#endif
