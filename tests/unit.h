#ifndef UNIT_H
#define UNIT_H

/* Minimal host-side test helpers. */

#include <stdio.h>

static int unit_pass = 0;
static int unit_fail = 0;

#define CHECK(cond) \
    do { \
        if (cond) { \
            unit_pass++; \
        } else { \
            unit_fail++; \
            printf("FAIL: %s:%d: %s\n", __FILE__, __LINE__, #cond); \
        } \
    } while (0)

#define UNIT_DONE() \
    (printf("%d passed, %d failed\n", unit_pass, unit_fail), \
     unit_fail != 0)

#endif
