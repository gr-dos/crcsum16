#include <string.h>
#include <dos.h>
#include "dosglob.h"

#define PATHSIZE  144

static char path[PATHSIZE];
static struct find_t ff;

int dosglob(const char *pattern, int (*fn)(const char *name))
{
    size_t dirlen = 0;
    size_t i;
    int rc = 0, r, matches = 0;

    if (strchr(pattern, '*') == NULL && strchr(pattern, '?') == NULL)
        return fn(pattern);

    for (i = 0; pattern[i]; i++)
        if (pattern[i] == '\\' || pattern[i] == '/' || pattern[i] == ':')
            dirlen = i + 1;
    if (dirlen + sizeof ff.name > PATHSIZE)
        return DOSGLOB_TOOLONG;

    if (_dos_findfirst(pattern, _A_NORMAL | _A_RDONLY | _A_HIDDEN
                       | _A_SYSTEM | _A_ARCH, &ff) != 0)
        return DOSGLOB_NOMATCH;
    do {
        if (ff.attrib & (_A_SUBDIR | _A_VOLID))
            continue;
        memcpy(path, pattern, dirlen);
        strcpy(path + dirlen, ff.name);
        matches++;
        r = fn(path);
        if (r > rc)
            rc = r;
    } while (_dos_findnext(&ff) == 0);

    return matches ? rc : DOSGLOB_NOMATCH;
}
