#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <inttypes.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

static double now_seconds(void) {
    struct timespec ts;
    if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0) {
        perror("clock_gettime");
        exit(2);
    }
    return (double)ts.tv_sec + (double)ts.tv_nsec / 1000000000.0;
}

struct cpu_args {
    double seconds;
    uint64_t ops;
    uint64_t result;
    unsigned index;
};

static void *cpu_worker(void *opaque) {
    struct cpu_args *arg = (struct cpu_args *)opaque;
    uint64_t x = UINT64_C(0x9e3779b97f4a7c15) ^ ((uint64_t)arg->index << 32);
    uint64_t ops = 0;
    const uint64_t batch = 4096;
    double end = now_seconds() + arg->seconds;

    do {
        for (uint64_t i = 0; i < batch; ++i) {
            x ^= x >> 12;
            x ^= x << 25;
            x ^= x >> 27;
            x *= UINT64_C(2685821657736338717);
            x += UINT64_C(0xd6e8feb86659fd93);
        }
        ops += batch;
    } while (now_seconds() < end);

    arg->ops = ops;
    arg->result = x;
    return NULL;
}

static int run_cpu(unsigned threads, double seconds) {
    if (threads == 0 || threads > 256 || seconds <= 0.0 || seconds > 120.0) {
        fprintf(stderr, "invalid CPU benchmark arguments\n");
        return 2;
    }

    pthread_t *ids = calloc(threads, sizeof(*ids));
    struct cpu_args *args = calloc(threads, sizeof(*args));
    if (!ids || !args) {
        perror("calloc");
        free(ids);
        free(args);
        return 2;
    }

    double start = now_seconds();
    for (unsigned i = 0; i < threads; ++i) {
        args[i].seconds = seconds;
        args[i].index = i;
        int rc = pthread_create(&ids[i], NULL, cpu_worker, &args[i]);
        if (rc != 0) {
            fprintf(stderr, "pthread_create: %s\n", strerror(rc));
            free(ids);
            free(args);
            return 2;
        }
    }

    uint64_t total_ops = 0;
    uint64_t checksum = 0;
    for (unsigned i = 0; i < threads; ++i) {
        int rc = pthread_join(ids[i], NULL);
        if (rc != 0) {
            fprintf(stderr, "pthread_join: %s\n", strerror(rc));
            free(ids);
            free(args);
            return 2;
        }
        total_ops += args[i].ops;
        checksum ^= args[i].result;
    }
    double elapsed = now_seconds() - start;

    printf("metric=cpu,threads=%u,seconds=%.6f,ops=%" PRIu64 ",ops_per_sec=%.3f,checksum=%" PRIu64 "\n",
           threads, elapsed, total_ops, (double)total_ops / elapsed, checksum);

    free(ids);
    free(args);
    return 0;
}

static int cmp_double(const void *a, const void *b) {
    const double da = *(const double *)a;
    const double db = *(const double *)b;
    return (da > db) - (da < db);
}

static double median(double *values, size_t count) {
    qsort(values, count, sizeof(values[0]), cmp_double);
    if (count & 1) return values[count / 2];
    return (values[count / 2 - 1] + values[count / 2]) / 2.0;
}

static int run_memory(size_t array_mib) {
    if (array_mib < 8 || array_mib > 512) {
        fprintf(stderr, "array MiB must be between 8 and 512\n");
        return 2;
    }

    size_t bytes = array_mib * 1024ULL * 1024ULL;
    size_t count = bytes / sizeof(double);
    double *a = NULL, *b = NULL, *c = NULL;

    if (posix_memalign((void **)&a, 64, bytes) != 0 ||
        posix_memalign((void **)&b, 64, bytes) != 0 ||
        posix_memalign((void **)&c, 64, bytes) != 0) {
        fprintf(stderr, "memory allocation failed for three %zu MiB arrays\n", array_mib);
        free(a); free(b); free(c);
        return 2;
    }

    for (size_t i = 0; i < count; ++i) {
        a[i] = 1.0 + (double)(i & 7);
        b[i] = 2.0;
        c[i] = 0.5;
    }

    enum { REPS = 7 };
    double copy_bw[REPS], scale_bw[REPS], add_bw[REPS], triad_bw[REPS];

    for (int r = 0; r < REPS; ++r) {
        double t0, dt;

        t0 = now_seconds();
        for (size_t i = 0; i < count; ++i) c[i] = a[i];
        dt = now_seconds() - t0;
        copy_bw[r] = (2.0 * (double)bytes) / dt / (1024.0 * 1024.0);

        t0 = now_seconds();
        for (size_t i = 0; i < count; ++i) b[i] = 3.0 * c[i];
        dt = now_seconds() - t0;
        scale_bw[r] = (2.0 * (double)bytes) / dt / (1024.0 * 1024.0);

        t0 = now_seconds();
        for (size_t i = 0; i < count; ++i) c[i] = a[i] + b[i];
        dt = now_seconds() - t0;
        add_bw[r] = (3.0 * (double)bytes) / dt / (1024.0 * 1024.0);

        t0 = now_seconds();
        for (size_t i = 0; i < count; ++i) a[i] = b[i] + 3.0 * c[i];
        dt = now_seconds() - t0;
        triad_bw[r] = (3.0 * (double)bytes) / dt / (1024.0 * 1024.0);
    }

    volatile double checksum = 0.0;
    size_t stride = count / 1024;
    if (stride == 0) stride = 1;
    for (size_t i = 0; i < count; i += stride) checksum += a[i] + b[i] + c[i];

    printf("metric=memory,name=copy,array_mib=%zu,mib_per_sec=%.3f\n",
           array_mib, median(copy_bw, REPS));
    printf("metric=memory,name=scale,array_mib=%zu,mib_per_sec=%.3f\n",
           array_mib, median(scale_bw, REPS));
    printf("metric=memory,name=add,array_mib=%zu,mib_per_sec=%.3f\n",
           array_mib, median(add_bw, REPS));
    printf("metric=memory,name=triad,array_mib=%zu,mib_per_sec=%.3f\n",
           array_mib, median(triad_bw, REPS));
    printf("metric=memory_checksum,value=%.6f\n", checksum);

    free(a); free(b); free(c);
    return 0;
}

static int run_exec(char **argv) {
    if (!argv || !argv[0]) {
        fprintf(stderr, "--exec requires a command\n");
        return 2;
    }

    double start = now_seconds();
    pid_t pid = fork();
    if (pid < 0) {
        perror("fork");
        return 2;
    }
    if (pid == 0) {
        execvp(argv[0], argv);
        perror("execvp");
        _exit(127);
    }

    int status = 0;
    if (waitpid(pid, &status, 0) < 0) {
        perror("waitpid");
        return 2;
    }
    double elapsed = now_seconds() - start;

    int code = 255;
    if (WIFEXITED(status)) code = WEXITSTATUS(status);
    else if (WIFSIGNALED(status)) code = 128 + WTERMSIG(status);

    printf("metric=exec,seconds=%.6f,exit_code=%d\n", elapsed, code);
    return code == 0 ? 0 : code;
}

static int generate_file(const char *path, size_t mib) {
    if (!path || mib < 1 || mib > 512) {
        fprintf(stderr, "invalid --generate arguments\n");
        return 2;
    }

    FILE *f = fopen(path, "wb");
    if (!f) {
        perror("fopen");
        return 2;
    }

    const size_t block = 1024 * 1024;
    unsigned char *buf = malloc(block);
    if (!buf) {
        fclose(f);
        return 2;
    }

    for (size_t i = 0; i < block; ++i) {
        buf[i] = (unsigned char)(((i * 17U) ^ (i >> 5) ^ (i >> 13)) & 0xffU);
        if ((i & 4095U) < 3072U) buf[i] = (unsigned char)('A' + ((i >> 8) & 15U));
    }

    for (size_t m = 0; m < mib; ++m) {
        buf[(m * 7919U) % block] ^= (unsigned char)m;
        if (fwrite(buf, 1, block, f) != block) {
            perror("fwrite");
            free(buf);
            fclose(f);
            return 2;
        }
    }

    if (fflush(f) != 0 || fsync(fileno(f)) != 0) {
        perror("flush");
        free(buf);
        fclose(f);
        return 2;
    }

    free(buf);
    fclose(f);
    printf("metric=generate,mib=%zu,path=%s\n", mib, path);
    return 0;
}

static void usage(const char *name) {
    fprintf(stderr,
        "Usage:\n"
        "  %s --cpu THREADS SECONDS\n"
        "  %s --memory ARRAY_MIB\n"
        "  %s --exec COMMAND [ARGS...]\n"
        "  %s --generate PATH MIB\n",
        name, name, name, name);
}

int main(int argc, char **argv) {
    if (argc >= 4 && strcmp(argv[1], "--cpu") == 0) {
        unsigned threads = (unsigned)strtoul(argv[2], NULL, 10);
        double seconds = strtod(argv[3], NULL);
        return run_cpu(threads, seconds);
    }
    if (argc == 3 && strcmp(argv[1], "--memory") == 0) {
        size_t mib = (size_t)strtoull(argv[2], NULL, 10);
        return run_memory(mib);
    }
    if (argc >= 3 && strcmp(argv[1], "--exec") == 0) {
        return run_exec(&argv[2]);
    }
    if (argc == 4 && strcmp(argv[1], "--generate") == 0) {
        size_t mib = (size_t)strtoull(argv[3], NULL, 10);
        return generate_file(argv[2], mib);
    }

    usage(argv[0]);
    return 2;
}
