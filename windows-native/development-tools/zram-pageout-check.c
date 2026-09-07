/* Bounded validation, not an OOM stress test. Requires active RAM-only swap. */
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

int main(void) {
    const size_t bytes = 128U * 1024U * 1024U;
    const long page = sysconf(_SC_PAGESIZE);
    if (page != 4096) return 2;
    unsigned char *data = mmap(NULL, bytes, PROT_READ | PROT_WRITE,
                               MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (data == MAP_FAILED) { perror("mmap"); return 3; }
    for (size_t i = 0; i < bytes / (size_t)page; ++i)
        memset(data + i * (size_t)page, (int)(i % 251U), (size_t)page);
    if (madvise(data, bytes, MADV_PAGEOUT)) { perror("madvise"); return 4; }
    puts("a1625_pageout_ready bytes=134217728 hold_seconds=20");
    fflush(stdout);
    sleep(20);
    for (size_t i = 0; i < bytes / (size_t)page; ++i)
        if (data[i * (size_t)page] != (unsigned char)(i % 251U)) return 5;
    if (munmap(data, bytes)) return 6;
    puts("a1625_pageout_contents_verified");
    return 0;
}
