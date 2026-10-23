/*
 * crcsum - compute and check CRC-32 checksums
 *
 * An md5sum-style CRC-32 (ZIP/Ethernet) utility for 16-bit MS-DOS
 * (Open Watcom C).
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <io.h>
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

static void usage(FILE *fp)
{
    fprintf(fp,
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
        "deliberate tampering.\n");
}

static void try_help(void)
{
    fprintf(stderr, "Try 'crcsum --help' for more information.\n");
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

    if (crc_file(name, &crc) != 0) {
        fprintf(stderr, "%s: %s: %s\n", progname, name, strerror(errno));
        return RC_FAIL;
    }
    printf("%08lx *%s\n", crc, name);
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

    fp = fopen(listname, "rb");
    if (fp == NULL) {
        fprintf(stderr, "%s: %s: %s\n", progname, listname, strerror(errno));
        return RC_FATAL;
    }

    while ((len = manifest_getline(fp, linebuf, LINESIZE)) != MANIFEST_EOF) {
        lineno++;
        if (len == MANIFEST_IOERR) {
            fprintf(stderr, "%s: %s: %s\n", progname, listname,
                    strerror(errno));
            rc = RC_FATAL;
            break;
        }
        if (len == MANIFEST_LONG) {
            n_bad_format++;
            fprintf(stderr, "%s: %s: %lu: line too long\n",
                    progname, listname, lineno);
            continue;
        }
        switch (manifest_parse(linebuf, (unsigned)len, &want, &name)) {
        case MANIFEST_SKIP:
            continue;
        case MANIFEST_BAD:
            n_bad_format++;
            fprintf(stderr, "%s: %s: %lu: improperly formatted line\n",
                    progname, listname, lineno);
            continue;
        }

        if (crc_file(name, &got) != 0) {
            n_bad_read++;
            fprintf(stderr, "%s: %s: %s\n", progname, name, strerror(errno));
            printf("%s: FAILED open or read\n", name);
        } else if (got != want) {
            n_bad_sum++;
            printf("%s: FAILED\n", name);
        } else {
            n_ok++;
            printf("%s: OK\n", name);
        }
    }
    fclose(fp);

    if (rc == RC_OK && n_ok + n_bad_read + n_bad_sum + n_bad_format == 0) {
        fprintf(stderr, "%s: %s: no checksum lines found\n",
                progname, listname);
        return RC_FATAL;
    }

    if (n_bad_format)
        fprintf(stderr, "%s: WARNING: %lu line%s improperly formatted\n",
                progname, n_bad_format, n_bad_format == 1 ? " is" : "s are");
    if (n_bad_read)
        fprintf(stderr, "%s: WARNING: %lu listed file%s could not be read\n",
                progname, n_bad_read, n_bad_read == 1 ? "" : "s");
    if (n_bad_sum)
        fprintf(stderr, "%s: WARNING: %lu computed checksum%s did NOT match\n",
                progname, n_bad_sum, n_bad_sum == 1 ? "" : "s");

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
        fprintf(stderr, "%s: %s: no matching files\n", progname, pattern);
        return RC_FAIL;
    }
    if (r == DOSGLOB_TOOLONG) {
        fprintf(stderr, "%s: %s: path too long\n", progname, pattern);
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

    for (i = 1; i < argc; i++) {
        a = argv[i];

        if (endopts || a[0] != '-') {
            nfiles++;
            continue;
        }
        if (a[1] == '\0') {
            fprintf(stderr, "%s: reading standard input is not supported\n",
                    progname);
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
                printf("crcsum (dos-crcsum16) %s\n", VERSION);
                return RC_OK;
            } else {
                fprintf(stderr, "%s: unrecognized option '%s'\n", progname, a);
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
                fprintf(stderr, "%s: invalid option -- '%c'\n", progname, *a);
                try_help();
                return RC_FATAL;
            }
        }
        argv[i] = NULL;
    }

    if (nfiles == 0) {
        fprintf(stderr, "%s: missing %s operand\n", progname,
                check ? "MANIFEST" : "FILE");
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
        fprintf(stderr, "%s: write error: %s\n", progname, strerror(errno));
        rc = RC_FATAL;
    }
    return rc;
}
