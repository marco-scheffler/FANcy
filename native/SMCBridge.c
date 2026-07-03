/*
 * SMCBridge.c — C bridge for IOKit SMC access.
 * Reusable from Swift via bridging header.
 */

#include "SMCBridge.h"
#include <IOKit/IOKitLib.h>
#include <string.h>

/* ── SMC structures (must match kernel layout exactly) ────────────── */

typedef struct {
    char major, minor, build, reserved[1];
    uint16_t release;
} SMCVers_t;

typedef struct {
    uint16_t version, length;
    uint32_t cpuPLimit, gpuPLimit, memPLimit;
} SMCPLimit_t;

typedef struct {
    uint32_t dataSize;
    uint32_t dataType;
    char     dataAttributes;
} SMCKeyInfo_t;

typedef char SMCBytes_t[32];

typedef struct {
    uint32_t     key;
    SMCVers_t    vers;
    SMCPLimit_t  pLimit;
    SMCKeyInfo_t keyInfo;
    char         result;
    char         status;
    char         data8;
    uint32_t     data32;
    SMCBytes_t   bytes;
} SMCKeyData_t;

#define KERNEL_INDEX_SMC      2
#define SMC_CMD_READ_KEYINFO  9
#define SMC_CMD_READ_BYTES    5
#define SMC_CMD_WRITE_BYTES   6

/* ── Internal state ───────────────────────────────────────────────── */

static io_connect_t g_conn = 0;

static uint32_t _str2key(const char *s) {
    uint32_t v = 0;
    for (int i = 0; i < 4; i++)
        v = (v << 8) | (unsigned char)s[i];
    return v;
}

static kern_return_t _smc_call(SMCKeyData_t *in, SMCKeyData_t *out) {
    size_t sz = sizeof(SMCKeyData_t);
    return IOConnectCallStructMethod(g_conn, KERNEL_INDEX_SMC, in, sz, out, &sz);
}

/* ── Public API ───────────────────────────────────────────────────── */

int smc_bridge_open(void) {
    mach_port_t mp;
    kern_return_t r = IOMainPort(kIOMainPortDefault, &mp);
    if (r != kIOReturnSuccess) return -1;

    CFMutableDictionaryRef d = IOServiceMatching("AppleSMC");
    io_iterator_t it;
    r = IOServiceGetMatchingServices(mp, d, &it);
    if (r != kIOReturnSuccess) return -2;

    io_object_t dev = IOIteratorNext(it);
    IOObjectRelease(it);
    if (!dev) return -3;

    r = IOServiceOpen(dev, mach_task_self(), 0, &g_conn);
    IOObjectRelease(dev);
    return (r == kIOReturnSuccess) ? 0 : -4;
}

void smc_bridge_close(void) {
    if (g_conn) {
        IOServiceClose(g_conn);
        g_conn = 0;
    }
}

float smc_bridge_read_float(const char *key4) {
    SMCKeyData_t in = {0}, info = {0}, val = {0};

    in.key = _str2key(key4);
    in.data8 = SMC_CMD_READ_KEYINFO;
    if (_smc_call(&in, &info) != kIOReturnSuccess) return -1.0f;

    in.keyInfo.dataSize = info.keyInfo.dataSize;
    in.data8 = SMC_CMD_READ_BYTES;
    if (_smc_call(&in, &val) != kIOReturnSuccess) return -1.0f;

    if (info.keyInfo.dataType == _str2key("flt ") && info.keyInfo.dataSize >= 4) {
        float f;
        memcpy(&f, val.bytes, 4);
        return f;
    }
    /* fallback fpe2 (Intel Macs) */
    if (info.keyInfo.dataType == _str2key("fpe2") && info.keyInfo.dataSize >= 2) {
        return ((unsigned char)val.bytes[0] << 8 |
                (unsigned char)val.bytes[1]) / 4.0f;
    }
    return -1.0f;
}

int smc_bridge_read_ui8(const char *key4) {
    SMCKeyData_t in = {0}, info = {0}, val = {0};

    in.key = _str2key(key4);
    in.data8 = SMC_CMD_READ_KEYINFO;
    if (_smc_call(&in, &info) != kIOReturnSuccess) return -1;

    in.keyInfo.dataSize = info.keyInfo.dataSize;
    in.data8 = SMC_CMD_READ_BYTES;
    if (_smc_call(&in, &val) != kIOReturnSuccess) return -1;

    return (unsigned char)val.bytes[0];
}

int smc_bridge_write_float(const char *key4, float value) {
    SMCKeyData_t in = {0}, info = {0}, out = {0};

    in.key = _str2key(key4);
    in.data8 = SMC_CMD_READ_KEYINFO;
    if (_smc_call(&in, &info) != kIOReturnSuccess) return -1;

    memset(&in, 0, sizeof(in));
    in.key = _str2key(key4);
    in.keyInfo.dataSize = info.keyInfo.dataSize;
    in.data8 = SMC_CMD_WRITE_BYTES;
    memcpy(in.bytes, &value, 4);

    return (_smc_call(&in, &out) == kIOReturnSuccess) ? 0 : -2;
}

int smc_bridge_write_ui8(const char *key4, uint8_t value) {
    SMCKeyData_t in = {0}, info = {0}, out = {0};

    in.key = _str2key(key4);
    in.data8 = SMC_CMD_READ_KEYINFO;
    if (_smc_call(&in, &info) != kIOReturnSuccess) return -1;

    memset(&in, 0, sizeof(in));
    in.key = _str2key(key4);
    in.keyInfo.dataSize = info.keyInfo.dataSize;
    in.data8 = SMC_CMD_WRITE_BYTES;
    in.bytes[0] = value;

    return (_smc_call(&in, &out) == kIOReturnSuccess) ? 0 : -2;
}
