/*
 * smc_helper.c — Minimal SMC fan control for Apple Silicon Macs
 *
 * Usage:
 *   ./smc_helper read          — JSON output of fan speeds, temps, mode
 *   ./smc_helper set <fan> <rpm> — set fan to manual mode + target RPM
 *   ./smc_helper auto          — restore automatic fan control
 *
 * Must run as root (sudo) for write operations.
 * Compile: cc -O2 -o smc_helper smc_helper.c -framework IOKit -framework CoreFoundation
 */

#include <IOKit/IOKitLib.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ── SMC data structures ───────────────────────────────────────────── */

typedef struct {
    char major, minor, build, reserved[1];
    UInt16 release;
} SMCKeyData_vers_t;

typedef struct {
    UInt16 version, length;
    UInt32 cpuPLimit, gpuPLimit, memPLimit;
} SMCKeyData_pLimitData_t;

typedef struct {
    UInt32 dataSize;
    UInt32 dataType;
    char   dataAttributes;
} SMCKeyData_keyInfo_t;

typedef char SMCBytes_t[32];

typedef struct {
    UInt32                  key;
    SMCKeyData_vers_t       vers;
    SMCKeyData_pLimitData_t pLimitData;
    SMCKeyData_keyInfo_t    keyInfo;
    char                    result;
    char                    status;
    char                    data8;
    UInt32                  data32;
    SMCBytes_t              bytes;
} SMCKeyData_t;

#define KERNEL_INDEX_SMC      2
#define SMC_CMD_READ_KEYINFO  9
#define SMC_CMD_READ_BYTES    5
#define SMC_CMD_WRITE_BYTES   6

/* ── Globals ───────────────────────────────────────────────────────── */

static io_connect_t g_conn;

/* ── Helpers ───────────────────────────────────────────────────────── */

static UInt32 str2key(const char *s) {
    UInt32 v = 0;
    for (int i = 0; i < 4; i++)
        v = (v << 8) | (unsigned char)s[i];
    return v;
}

static kern_return_t smc_call(SMCKeyData_t *in, SMCKeyData_t *out) {
    size_t sz = sizeof(SMCKeyData_t);
    return IOConnectCallStructMethod(g_conn, KERNEL_INDEX_SMC, in, sz, out, &sz);
}

static kern_return_t smc_open(void) {
    mach_port_t mp;
    kern_return_t r = IOMainPort(kIOMainPortDefault, &mp);
    if (r != kIOReturnSuccess) return r;

    CFMutableDictionaryRef d = IOServiceMatching("AppleSMC");
    io_iterator_t it;
    r = IOServiceGetMatchingServices(mp, d, &it);
    if (r != kIOReturnSuccess) return r;

    io_object_t dev = IOIteratorNext(it);
    IOObjectRelease(it);
    if (!dev) return kIOReturnNotFound;

    r = IOServiceOpen(dev, mach_task_self(), 0, &g_conn);
    IOObjectRelease(dev);
    return r;
}

static void smc_close(void) {
    IOServiceClose(g_conn);
}

/* ── Read a single SMC key ─────────────────────────────────────────── */

static kern_return_t smc_read(const char *keyStr, SMCKeyData_t *info_out,
                              SMCKeyData_t *val_out) {
    SMCKeyData_t in = {0};
    *info_out = (SMCKeyData_t){0};

    in.key   = str2key(keyStr);
    in.data8 = SMC_CMD_READ_KEYINFO;

    kern_return_t r = smc_call(&in, info_out);
    if (r != kIOReturnSuccess) return r;

    in.keyInfo.dataSize = info_out->keyInfo.dataSize;
    in.data8 = SMC_CMD_READ_BYTES;

    *val_out = (SMCKeyData_t){0};
    r = smc_call(&in, val_out);
    if (r == kIOReturnSuccess)
        val_out->keyInfo = info_out->keyInfo;
    return r;
}

static float smc_read_float(const char *keyStr) {
    SMCKeyData_t info = {0}, val = {0};
    if (smc_read(keyStr, &info, &val) != kIOReturnSuccess) return -1.0f;
    if (info.keyInfo.dataType == str2key("flt ") && info.keyInfo.dataSize >= 4) {
        float f;
        memcpy(&f, val.bytes, 4);
        return f;
    }
    /* fallback fpe2 (older Macs) */
    if (info.keyInfo.dataType == str2key("fpe2") && info.keyInfo.dataSize >= 2)
        return ((unsigned char)val.bytes[0] << 8 | (unsigned char)val.bytes[1]) / 4.0f;
    return -1.0f;
}

static int smc_read_ui8(const char *keyStr) {
    SMCKeyData_t info = {0}, val = {0};
    if (smc_read(keyStr, &info, &val) != kIOReturnSuccess) return -1;
    return (unsigned char)val.bytes[0];
}

/* ── Write a single SMC key ────────────────────────────────────────── */

static kern_return_t smc_write_float(const char *keyStr, float value) {
    SMCKeyData_t info = {0}, dummy = {0};
    kern_return_t r = smc_read(keyStr, &info, &dummy);
    if (r != kIOReturnSuccess) return r;

    SMCKeyData_t in = {0}, out = {0};
    in.key = str2key(keyStr);
    in.keyInfo.dataSize = info.keyInfo.dataSize;
    in.data8 = SMC_CMD_WRITE_BYTES;
    memcpy(in.bytes, &value, 4);

    return smc_call(&in, &out);
}

static kern_return_t smc_write_ui8(const char *keyStr, UInt8 value) {
    SMCKeyData_t info = {0}, dummy = {0};
    kern_return_t r = smc_read(keyStr, &info, &dummy);
    if (r != kIOReturnSuccess) return r;

    SMCKeyData_t in = {0}, out = {0};
    in.key = str2key(keyStr);
    in.keyInfo.dataSize = info.keyInfo.dataSize;
    in.data8 = SMC_CMD_WRITE_BYTES;
    in.bytes[0] = value;

    return smc_call(&in, &out);
}

/* ── Read temperature keys ─────────────────────────────────────────── */

static float read_cpu_temp(void) {
    /* Apple Silicon: Tp00 = CPU die temp (highest P-core cluster) */
    const char *keys[] = {"Tp00", "Tp09", "Tp0T", "TC0P", NULL};
    for (int i = 0; keys[i]; i++) {
        float t = smc_read_float(keys[i]);
        if (t > 0 && t < 150) return t;
    }
    return -1.0f;
}

static float read_gpu_temp(void) {
    /* Apple Silicon: Tg08 = GPU cluster temp */
    const char *keys[] = {"Tg08", "Tg0C", "Tg0O", "TG0P", NULL};
    for (int i = 0; keys[i]; i++) {
        float t = smc_read_float(keys[i]);
        if (t > 0 && t < 150) return t;
    }
    return -1.0f;
}

/* ── Commands ──────────────────────────────────────────────────────── */

static void cmd_read(void) {
    int num_fans = smc_read_ui8("FNum");
    if (num_fans < 0) num_fans = 0;

    float cpu_temp = read_cpu_temp();
    float gpu_temp = read_gpu_temp();

    printf("{\"fans\":%d,\"cpu_temp\":%.1f,\"gpu_temp\":%.1f,\"fan_data\":[",
           num_fans, cpu_temp, gpu_temp);

    for (int i = 0; i < num_fans; i++) {
        char k[5];
        snprintf(k, 5, "F%dAc", i); float actual = smc_read_float(k);
        snprintf(k, 5, "F%dMn", i); float mn     = smc_read_float(k);
        snprintf(k, 5, "F%dMx", i); float mx     = smc_read_float(k);
        snprintf(k, 5, "F%dTg", i); float tg     = smc_read_float(k);
        snprintf(k, 5, "F%dmd", i); int   manual  = smc_read_ui8(k);

        if (i > 0) printf(",");
        printf("{\"id\":%d,\"actual\":%.0f,\"min\":%.0f,\"max\":%.0f,"
               "\"target\":%.0f,\"manual\":%d}",
               i, actual, mn, mx, tg, manual);
    }
    printf("]}\n");
}

static void cmd_set(int fan, float rpm) {
    char k[5];

    /* Clamp to min/max */
    snprintf(k, 5, "F%dMn", fan); float mn = smc_read_float(k);
    snprintf(k, 5, "F%dMx", fan); float mx = smc_read_float(k);
    if (mn > 0 && rpm < mn) rpm = mn;
    if (mx > 0 && rpm > mx) rpm = mx;

    /* Enable manual mode */
    snprintf(k, 5, "F%dmd", fan);
    kern_return_t r = smc_write_ui8(k, 1);
    if (r != kIOReturnSuccess) {
        fprintf(stderr, "{\"error\":\"failed to set manual mode for fan %d: %d\"}\n", fan, r);
        return;
    }

    /* Set target RPM */
    snprintf(k, 5, "F%dTg", fan);
    r = smc_write_float(k, rpm);
    if (r != kIOReturnSuccess) {
        fprintf(stderr, "{\"error\":\"failed to set target RPM for fan %d: %d\"}\n", fan, r);
        return;
    }

    printf("{\"ok\":true,\"fan\":%d,\"rpm\":%.0f}\n", fan, rpm);
}

static void cmd_auto(void) {
    int num_fans = smc_read_ui8("FNum");
    if (num_fans < 0) num_fans = 2;

    int ok = 1;
    for (int i = 0; i < num_fans; i++) {
        char k[5];
        snprintf(k, 5, "F%dmd", i);
        kern_return_t r = smc_write_ui8(k, 0);
        if (r != kIOReturnSuccess) {
            fprintf(stderr, "{\"error\":\"failed to reset fan %d to auto: %d\"}\n", i, r);
            ok = 0;
        }
    }
    if (ok) printf("{\"ok\":true,\"mode\":\"auto\"}\n");
}

/* ── Main ──────────────────────────────────────────────────────────── */

int main(int argc, char *argv[]) {
    if (argc < 2) {
        fprintf(stderr, "Usage: %s read | set <fan> <rpm> | auto\n", argv[0]);
        return 1;
    }

    if (smc_open() != kIOReturnSuccess) {
        fprintf(stderr, "{\"error\":\"failed to open SMC connection\"}\n");
        return 1;
    }

    if (strcmp(argv[1], "read") == 0) {
        cmd_read();
    } else if (strcmp(argv[1], "set") == 0 && argc >= 4) {
        int fan = atoi(argv[2]);
        float rpm = atof(argv[3]);
        cmd_set(fan, rpm);
    } else if (strcmp(argv[1], "auto") == 0) {
        cmd_auto();
    } else {
        fprintf(stderr, "Usage: %s read | set <fan> <rpm> | auto\n", argv[0]);
        smc_close();
        return 1;
    }

    smc_close();
    return 0;
}
