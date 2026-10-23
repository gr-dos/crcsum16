#ifndef DOSGLOB_H
#define DOSGLOB_H

/* dosglob results besides fn's own (which must be >= 0) */
#define DOSGLOB_NOMATCH  (-1)   /* a wildcard matched no file */
#define DOSGLOB_TOOLONG  (-2)   /* the pattern's directory is too long */

/*
 * If pattern has no DOS wildcard (* or ?), call fn(pattern).
 * Otherwise call fn on every matching file, skipping directories and
 * volume labels, in the order DOS returns them; each name is the
 * pattern's directory part followed by the name as DOS returns it.
 * Returns the largest fn result, or DOSGLOB_NOMATCH / DOSGLOB_TOOLONG.
 */
int dosglob(const char *pattern, int (*fn)(const char *name));

#endif
