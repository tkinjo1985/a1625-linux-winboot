#pragma once

#if defined(__MINGW32__) || defined(__CYGWIN__)
#include <errno.h>
#include <stddef.h>
#include <sys/types.h>

#ifndef O_LARGEFILE
#define O_LARGEFILE 0
#endif

/* gen_init_cpio already falls back to read/write when this returns -1. */
static inline ssize_t kbuild_copy_file_range(int fd_in, off_t *off_in,
                                             int fd_out, off_t *off_out,
                                             size_t len, unsigned int flags)
{
    (void)fd_in;
    (void)off_in;
    (void)fd_out;
    (void)off_out;
    (void)len;
    (void)flags;
    errno = ENOSYS;
    return -1;
}

#define copy_file_range kbuild_copy_file_range

static inline const char *kbuild_strchrnul(const char *text, int character)
{
    while (*text && *text != (char)character)
        text++;
    return text;
}

#define strchrnul kbuild_strchrnul
#endif
