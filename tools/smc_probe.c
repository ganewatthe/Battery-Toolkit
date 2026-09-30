/*
 * Probe SMC key info and values, to check which power control keys the
 * current SMC firmware exposes. Useful when a macOS update changes the
 * SMC key set and the daemon reports the machine as unsupported.
 *
 * Build: xcrun clang tools/smc_probe.c -o /tmp/smc_probe \
 *            -framework IOKit -framework CoreFoundation \
 *            -I Modules/SMCParamStruct
 * Usage: /tmp/smc_probe [key ...]   (defaults to the known power keys)
 */

#include <stdio.h>
#include <string.h>
#include <IOKit/IOKitLib.h>
#include "SMCParamStruct.h"

static io_connect_t connect = IO_OBJECT_NULL;

static IOReturn callSMC(SMCParamStruct *in, SMCParamStruct *out) {
    size_t size = sizeof(SMCParamStruct);
    IOReturn ret = IOConnectCallStructMethod(
        connect, kSMCHandleYPCEvent, in, sizeof(SMCParamStruct), out, &size
    );
    if (ret != kIOReturnSuccess) {
        return ret;
    }
    return out->result;
}

static uint32_t keyFrom(const char *name) {
    return ((uint32_t)name[0] << 24) | ((uint32_t)name[1] << 16) |
        ((uint32_t)name[2] << 8) | (uint32_t)name[3];
}

static void probeInfo(const char *name) {
    SMCParamStruct in = {0}, out = {0};
    in.key = keyFrom(name);
    in.data8 = kSMCGetKeyInfo;
    IOReturn result = callSMC(&in, &out);
    if (result != kSMCSuccess) {
        printf("%s: not found (result=%u)\n", name, result);
        return;
    }

    printf("%s: size=%u type=%c%c%c%c attr=0x%x\n", name,
        out.keyInfo.dataSize,
        (char)(out.keyInfo.dataType >> 24), (char)(out.keyInfo.dataType >> 16),
        (char)(out.keyInfo.dataType >> 8), (char)(out.keyInfo.dataType),
        out.keyInfo.dataAttributes);
}

static void probeValue(const char *name) {
    SMCParamStruct in = {0}, out = {0};
    in.key = keyFrom(name);
    in.keyInfo.dataSize = 4;
    in.data8 = kSMCReadKey;
    IOReturn result = callSMC(&in, &out);
    if (result != kSMCSuccess) {
        printf("%s: read failed (result=%u)\n", name, result);
        return;
    }

    printf("%s bytes:", name);
    for (unsigned i = 0; i < 4; i++) {
        printf(" %02x", out.bytes[i]);
    }
    uint32_t le = (uint32_t)out.bytes[0] | ((uint32_t)out.bytes[1] << 8) |
        ((uint32_t)out.bytes[2] << 16) | ((uint32_t)out.bytes[3] << 24);
    printf("  (LE u32: %u)\n", le);
}

static bool writeValue(const char *name, const char *hexBytes) {
    size_t count = strlen(hexBytes) / 2;
    if (count == 0 || count > 4) {
        printf("%s: invalid write value %s\n", name, hexBytes);
        return false;
    }

    uint8_t bytes[4] = {0};
    for (size_t i = 0; i < count; i++) {
        unsigned b = 0;
        if (sscanf(hexBytes + 2 * i, "%2x", &b) != 1) {
            printf("%s: invalid hex %s\n", name, hexBytes);
            return false;
        }
        bytes[i] = (uint8_t)b;
    }

    SMCParamStruct in = {0}, out = {0};
    in.key = keyFrom(name);
    in.keyInfo.dataSize = (uint32_t)count;
    in.data8 = kSMCWriteKey;
    memcpy(in.bytes, bytes, count);
    IOReturn result = callSMC(&in, &out);
    if (result != kSMCSuccess) {
        printf("%s: write failed (result=%u)\n", name, result);
        return false;
    }

    printf("%s: wrote %zu byte(s):", name, count);
    for (size_t i = 0; i < count; i++) {
        printf(" %02x", bytes[i]);
    }
    printf("\n");

    probeValue(name);
    return true;
}

int main(int argc, char **argv) {
    setvbuf(stdout, NULL, _IOLBF, 0);

    io_service_t smc = IOServiceGetMatchingService(
        kIOMainPortDefault, IOServiceMatching("AppleSMC")
    );
    if (smc == IO_OBJECT_NULL) {
        printf("no AppleSMC\n");
        return 1;
    }
    IOReturn ret = IOServiceOpen(smc, mach_task_self_, 1, &connect);
    if (ret != kIOReturnSuccess) {
        printf("open failed 0x%x\n", ret);
        return 1;
    }
    IOConnectCallMethod(
        connect, kSMCUserClientOpen, NULL, 0, NULL, 0, NULL, NULL, NULL, NULL
    );

    if (argc > 1) {
        for (int i = 1; i < argc; i++) {
            char *eq = strchr(argv[i], '=');
            if (eq != NULL) {
                *eq = '\0';
                probeInfo(argv[i]);
                writeValue(argv[i], eq + 1);
                continue;
            }
            probeInfo(argv[i]);
            probeValue(argv[i]);
        }
        return 0;
    }

    const char *keys[] = {
        "CH0B", "CH0C", "CH0D", "CH0I", "CH0J", "CHIE", "CHTE",
        "bfF0", "bfD0", "bfE0"
    };
    for (unsigned i = 0; i < sizeof(keys) / sizeof(keys[0]); i++) {
        probeInfo(keys[i]);
        probeValue(keys[i]);
    }
    return 0;
}