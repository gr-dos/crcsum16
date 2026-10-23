#ifndef MANIFEST_H
#define MANIFEST_H

#include <stdio.h>

/*
 * Checksum manifest lines:
 *   <8 hex digits><space><'*' or space><filename>
 * Blank lines and lines starting with '#' are skipped.
 */

/* manifest_getline results (lengths are >= 0) */
#define MANIFEST_EOF    (-1)
#define MANIFEST_LONG   (-2)    /* line too long; the rest was discarded */
#define MANIFEST_IOERR  (-3)

/* manifest_parse results */
#define MANIFEST_ENTRY  0
#define MANIFEST_SKIP   1       /* blank or comment */
#define MANIFEST_BAD    (-1)

/*
 * Read one line from fp (opened in binary mode) into buf, without its
 * terminator, and return its length.  A line ends at LF, CR LF, a lone
 * CR, or end of file; Ctrl-Z marks end of file.  The last line need not
 * be terminated.  Lines of size bytes or more are rejected whole.
 */
int manifest_getline(FILE *fp, char *buf, unsigned size);

/*
 * Parse a line of len bytes from manifest_getline.  For an entry, sets
 * *crc and points *name into line.
 */
int manifest_parse(char *line, unsigned len, unsigned long *crc,
                   char **name);

#endif
