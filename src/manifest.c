#include <string.h>
#include "manifest.h"

#define CTRL_Z  0x1a

int manifest_getline(FILE *fp, char *buf, unsigned size)
{
    unsigned len = 0;
    int c, too_long = 0;

    for (;;) {
        c = getc(fp);
        if (c == EOF || c == CTRL_Z) {
            if (c == CTRL_Z)
                ungetc(c, fp);      /* so every later call sees EOF too */
            else if (ferror(fp))
                return MANIFEST_IOERR;
            if (len == 0 && !too_long)
                return MANIFEST_EOF;
            break;
        }
        if (c == '\n')
            break;
        if (c == '\r') {
            c = getc(fp);
            if (c != '\n' && c != EOF)
                ungetc(c, fp);
            break;
        }
        if (len + 1 < size)
            buf[len++] = (char)c;
        else
            too_long = 1;
    }
    if (too_long)
        return MANIFEST_LONG;
    buf[len] = '\0';
    return (int)len;
}

static int hexval(int c)
{
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

int manifest_parse(char *line, unsigned len, unsigned long *crc,
                   char **name)
{
    unsigned long v = 0;
    int i, d;

    if (len == 0 || line[0] == '#')
        return MANIFEST_SKIP;
    if (strlen(line) != len)            /* embedded NUL */
        return MANIFEST_BAD;
    if (len < 8 + 2 + 1)
        return MANIFEST_BAD;
    for (i = 0; i < 8; i++) {
        d = hexval((unsigned char)line[i]);
        if (d < 0)
            return MANIFEST_BAD;
        v = (v << 4) | (unsigned long)d;
    }
    if (line[8] != ' ' || (line[9] != '*' && line[9] != ' '))
        return MANIFEST_BAD;
    *crc = v;
    *name = line + 10;
    return MANIFEST_ENTRY;
}
