/* Host-side tests for manifest.c. */

#include <string.h>
#include "manifest.h"
#include "unit.h"

#define SIZE 32

static char buf[SIZE];

/* Open a temporary file holding len bytes of data, rewound. */
static FILE *input(const char *data, unsigned len)
{
    FILE *fp = tmpfile();

    if (fp == NULL) {
        perror("tmpfile");
        return NULL;
    }
    fwrite(data, 1, len, fp);
    rewind(fp);
    return fp;
}

#define INPUT(s) input(s, sizeof(s) - 1)

/* Next line is exactly s. */
static int line_is(FILE *fp, const char *s)
{
    int n = manifest_getline(fp, buf, SIZE);
    return n >= 0 && (unsigned)n == strlen(s) && strcmp(buf, s) == 0;
}

static int at_eof(FILE *fp)
{
    return manifest_getline(fp, buf, SIZE) == MANIFEST_EOF
        && manifest_getline(fp, buf, SIZE) == MANIFEST_EOF;
}

static void test_getline(void)
{
    FILE *fp;

    /* empty input */
    fp = INPUT("");
    CHECK(at_eof(fp));
    fclose(fp);

    /* LF, CR LF, lone CR, and a missing final newline */
    fp = INPUT("one\ntwo\r\nthree\rfour\r\n\nlast");
    CHECK(line_is(fp, "one"));
    CHECK(line_is(fp, "two"));
    CHECK(line_is(fp, "three"));
    CHECK(line_is(fp, "four"));
    CHECK(line_is(fp, ""));
    CHECK(line_is(fp, "last"));
    CHECK(at_eof(fp));
    fclose(fp);

    /* CR at the very end */
    fp = INPUT("a\r");
    CHECK(line_is(fp, "a"));
    CHECK(at_eof(fp));
    fclose(fp);

    /* Ctrl-Z ends the file, with or without a pending line */
    fp = INPUT("a\r\n\032junk\n");
    CHECK(line_is(fp, "a"));
    CHECK(at_eof(fp));
    fclose(fp);
    fp = INPUT("a\032junk\n");
    CHECK(line_is(fp, "a"));
    CHECK(at_eof(fp));
    fclose(fp);

    /* longest line that fits, then one too long, then recovery */
    fp = INPUT("0123456789012345678901234567890\n"
               "01234567890123456789012345678901\n"
               "ok");
    CHECK(line_is(fp, "0123456789012345678901234567890"));
    CHECK(manifest_getline(fp, buf, SIZE) == MANIFEST_LONG);
    CHECK(line_is(fp, "ok"));
    CHECK(at_eof(fp));
    fclose(fp);

    /* an overlong unterminated last line */
    fp = INPUT("0123456789012345678901234567890123456789");
    CHECK(manifest_getline(fp, buf, SIZE) == MANIFEST_LONG);
    CHECK(at_eof(fp));
    fclose(fp);

    /* embedded NUL is kept, so parse can reject it */
    fp = INPUT("ab\0cd\n");
    CHECK(manifest_getline(fp, buf, SIZE) == 5);
    fclose(fp);
}

static int parse(const char *s, unsigned long *crc, char **name)
{
    strcpy(buf, s);
    return manifest_parse(buf, (unsigned)strlen(s), crc, name);
}

static void test_parse(void)
{
    unsigned long crc;
    char *name;

    CHECK(parse("cbf43926 *123456789.TXT", &crc, &name) == MANIFEST_ENTRY);
    CHECK(crc == 0xCBF43926UL);
    CHECK(strcmp(name, "123456789.TXT") == 0);

    /* GNU text marker and upper case hex */
    CHECK(parse("CBF43926  a.txt", &crc, &name) == MANIFEST_ENTRY);
    CHECK(crc == 0xCBF43926UL);
    CHECK(strcmp(name, "a.txt") == 0);

    CHECK(parse("00000000 *SUB\\E.DAT", &crc, &name) == MANIFEST_ENTRY);
    CHECK(crc == 0);
    CHECK(strcmp(name, "SUB\\E.DAT") == 0);
    CHECK(parse("ffffffff *x", &crc, &name) == MANIFEST_ENTRY);
    CHECK(crc == 0xFFFFFFFFUL);

    /* blank lines and comments */
    CHECK(parse("", &crc, &name) == MANIFEST_SKIP);
    CHECK(parse("# made on Phaistos", &crc, &name) == MANIFEST_SKIP);

    /* malformed */
    CHECK(parse("cbf4392g *a", &crc, &name) == MANIFEST_BAD);   /* bad hex */
    CHECK(parse("cbf4392 *ab", &crc, &name) == MANIFEST_BAD);   /* 7 digits */
    CHECK(parse("cbf439260 *a", &crc, &name) == MANIFEST_BAD);  /* 9 digits */
    CHECK(parse("cbf43926 a.txt", &crc, &name) == MANIFEST_BAD); /* no marker */
    CHECK(parse("cbf43926*a.txt", &crc, &name) == MANIFEST_BAD);
    CHECK(parse("cbf43926 *", &crc, &name) == MANIFEST_BAD);    /* no name */
    CHECK(parse("cbf43926  ", &crc, &name) == MANIFEST_BAD);
    CHECK(parse("cbf43926", &crc, &name) == MANIFEST_BAD);
    CHECK(parse(" cbf43926 *a", &crc, &name) == MANIFEST_BAD);
    CHECK(parse("CRC32 (a) = cbf43926", &crc, &name) == MANIFEST_BAD);

    /* embedded NUL */
    memcpy(buf, "cbf43926 *a\0b", 13);
    CHECK(manifest_parse(buf, 13, &crc, &name) == MANIFEST_BAD);
}

int main(void)
{
    test_getline();
    test_parse();
    return UNIT_DONE();
}
