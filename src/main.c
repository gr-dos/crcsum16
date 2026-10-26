/*
 * crcsum - compute and check CRC-32 checksums
 *
 * An md5sum-style CRC-32 (ZIP/Ethernet) utility for 16-bit MS-DOS
 * (Open Watcom C with libc16).
 */

#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <io.h>
#include <libc16.h>
#include "crc32.h"
#include "manifest.h"
#include "dosglob.h"

#ifndef VERSION
#define VERSION   "unknown"
#endif

#define BUFSIZE   16384
#define LINESIZE  256

/* exit statuses, also used as "worst so far" */
#define RC_OK     0
#define RC_FAIL   1     /* missing, unreadable or mismatched file */
#define RC_FATAL  2     /* usage error, bad manifest, write error */

static unsigned char iobuf[BUFSIZE];
static char linebuf[LINESIZE];

static const char *progname = "crcsum";

/* errno from the first failed write to standard output, before later
 * calls (such as the end of a wildcard search) change errno */
static int write_errno;

/* Writes the strings, up to a null pointer, to fp. */
static void put(FILE *fp, const char *s, ...)
{
    va_list ap;

    va_start(ap, s);
    for (; s != NULL; s = va_arg(ap, const char *))
        if (fputs(s, fp) == EOF && fp == stdout && write_errno == 0)
            write_errno = errno;
    va_end(ap);
}

/* "crcsum: A: B\n" on standard error */
static void error2(const char *a, const char *b)
{
    put(stderr, progname, ": ", a, ": ", b, "\n", NULL);
}

/* n in decimal, in buf (12 bytes) */
static char *dec(unsigned long n, char *buf)
{
    return libc16_ultoa(n, buf, 10);
}

static void usage(FILE *fp)
{
    fputs(
        "Usage: crcsum FILE...\n"
        "  or:  crcsum -c MANIFEST...\n"
        "Print or check CRC-32 (ZIP/Ethernet) checksums.\n"
        "Wildcards (* and ?) in FILE are expanded.\n"
        "\n"
        "  -c, --check    read checksums from the MANIFESTs and check them\n"
        "  -h, -?, --help display this help and exit\n"
        "      --version  output version information and exit\n"
        "      --         treat the remaining arguments as files\n"
        "\n"
        "ERRORLEVEL is 0 if all files were read and all checksums matched,\n"
        "1 if a file was missing, unreadable or did not match, or a wildcard\n"
        "matched nothing, and 2 for a usage error, an unreadable or\n"
        "malformed manifest, or an output write error.\n"
        "\n"
        "CRC-32 detects accidental corruption; it is not secure against\n"
        "deliberate tampering.\n", fp);
}

static void try_help(void)
{
    fputs("Try 'crcsum --help' for more information.\n", stderr);
}

/* CRC of a named file.  Returns 0 on success, -1 with errno set. */
static int crc_file(const char *name, crc32_t *crc)
{
    int fd, n, err;
    crc32_t c = CRC32_INIT;

    fd = open(name, O_RDONLY | O_BINARY);
    if (fd < 0)
        return -1;
    while ((n = read(fd, iobuf, BUFSIZE)) > 0)
        c = crc32_update(c, iobuf, (unsigned)n);
    err = errno;                /* close may clobber a read error */
    close(fd);
    if (n < 0) {
        errno = err;
        return -1;
    }
    *crc = CRC32_FINAL(c);
    return 0;
}

static int sum_one(const char *name)
{
    crc32_t crc;
    char hex[9];
    int i;

    if (crc_file(name, &crc) != 0) {
        error2(name, strerror(errno));
        return RC_FAIL;
    }
    for (i = 7; i >= 0; i--, crc >>= 4)
        hex[i] = "0123456789abcdef"[(unsigned)crc & 15];
    hex[8] = '\0';
    put(stdout, hex, " *", name, "\n", NULL);
    return RC_OK;
}

static int check_list(const char *listname)
{
    FILE *fp;
    crc32_t want, got;
    char *name;
    int len;
    unsigned long lineno = 0;
    unsigned long n_ok = 0, n_bad_format = 0, n_bad_read = 0, n_bad_sum = 0;
    int rc = RC_OK;
    char num[12];

    fp = fopen(listname, "rb");
    if (fp == NULL) {
        error2(listname, strerror(errno));
        return RC_FATAL;
    }

    while ((len = manifest_getline(fp, linebuf, LINESIZE)) != MANIFEST_EOF) {
        lineno++;
        if (len == MANIFEST_IOERR) {
            error2(listname, strerror(errno));
            rc = RC_FATAL;
            break;
        }
        if (len == MANIFEST_LONG) {
            n_bad_format++;
            put(stderr, progname, ": ", listname, ": ", dec(lineno, num),
                ": line too long\n", NULL);
            continue;
        }
        switch (manifest_parse(linebuf, (unsigned)len, &want, &name)) {
        case MANIFEST_SKIP:
            continue;
        case MANIFEST_BAD:
            n_bad_format++;
            put(stderr, progname, ": ", listname, ": ", dec(lineno, num),
                ": improperly formatted line\n", NULL);
            continue;
        }

        if (crc_file(name, &got) != 0) {
            n_bad_read++;
            error2(name, strerror(errno));
            put(stdout, name, ": FAILED open or read\n", NULL);
        } else if (got != want) {
            n_bad_sum++;
            put(stdout, name, ": FAILED\n", NULL);
        } else {
            n_ok++;
            put(stdout, name, ": OK\n", NULL);
        }
    }
    fclose(fp);

    if (rc == RC_OK && n_ok + n_bad_read + n_bad_sum + n_bad_format == 0) {
        error2(listname, "no checksum lines found");
        return RC_FATAL;
    }

    if (n_bad_format)
        put(stderr, progname, ": WARNING: ", dec(n_bad_format, num), " line",
            n_bad_format == 1 ? " is" : "s are", " improperly formatted\n",
            NULL);
    if (n_bad_read)
        put(stderr, progname, ": WARNING: ", dec(n_bad_read, num),
            " listed file", n_bad_read == 1 ? "" : "s", " could not be read\n",
            NULL);
    if (n_bad_sum)
        put(stderr, progname, ": WARNING: ", dec(n_bad_sum, num),
            " computed checksum", n_bad_sum == 1 ? "" : "s", " did NOT match\n",
            NULL);

    if (n_bad_format)
        rc = RC_FATAL;
    else if (rc == RC_OK && (n_bad_read || n_bad_sum))
        rc = RC_FAIL;
    return rc;
}

static int sum_arg(const char *pattern)
{
    int r = dosglob(pattern, sum_one);

    if (r == DOSGLOB_NOMATCH) {
        error2(pattern, "no matching files");
        return RC_FAIL;
    }
    if (r == DOSGLOB_TOOLONG) {
        error2(pattern, "path too long");
        return RC_FAIL;
    }
    return r;
}

int main(int argc, char **argv)
{
    int check = 0;
    int i, nfiles = 0, endopts = 0;
    int rc = RC_OK, r;
    const char *a;
    char opt[2] = { 0, 0 };

    for (i = 1; i < argc; i++) {
        a = argv[i];

        if (endopts || a[0] != '-') {
            nfiles++;
            continue;
        }
        if (a[1] == '\0') {
            put(stderr, progname, ": reading standard input is not supported\n",
                NULL);
            try_help();
            return RC_FATAL;
        }
        if (a[1] == '-') {
            if (a[2] == '\0')
                endopts = 1;
            else if (stricmp(a, "--check") == 0)
                check = 1;
            else if (stricmp(a, "--help") == 0) {
                usage(stdout);
                return RC_OK;
            } else if (stricmp(a, "--version") == 0) {
                fputs("crcsum (crcsum16) " VERSION "\n", stdout);
                return RC_OK;
            } else {
                put(stderr, progname, ": unrecognized option '", a, "'\n",
                    NULL);
                try_help();
                return RC_FATAL;
            }
            argv[i] = NULL;
            continue;
        }
        for (a++; *a; a++) {
            switch (*a) {
            case 'c':
            case 'C':
                check = 1;
                break;
            case 'h':
            case 'H':
            case '?':
                usage(stdout);
                return RC_OK;
            default:
                opt[0] = *a;
                put(stderr, progname, ": invalid option -- '", opt, "'\n",
                    NULL);
                try_help();
                return RC_FATAL;
            }
        }
        argv[i] = NULL;
    }

    if (nfiles == 0) {
        put(stderr, progname, ": missing ", check ? "MANIFEST" : "FILE",
            " operand\n", NULL);
        try_help();
        return RC_FATAL;
    }

    crc32_init();

    for (i = 1; i < argc; i++) {
        if (argv[i] == NULL)
            continue;
        r = check ? check_list(argv[i]) : sum_arg(argv[i]);
        if (r > rc)
            rc = r;
    }

    if (fflush(stdout) != 0 || ferror(stdout)) {
        error2("write error", strerror(write_errno ? write_errno : errno));
        rc = RC_FATAL;
    }
    return rc;
}
