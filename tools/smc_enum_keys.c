/*
 * Enumerate SMC keys with a given prefix, printing key info for each match.
 * Useful to discover which keys a new SMC firmware exposes, e.g., when
 * looking for the successor of a removed charging control key.
 *
 * Note: the SMC key count cannot be trusted on all firmwares, so keys are
 * iterated by index until a long run of lookups fails.
 *
 * Build: xcrun clang tools/smc_enum_keys.c -o /tmp/smc_enum \
 *            -framework IOKit -framework CoreFoundation \
 *            -I Modules/SMCParamStruct
 * Usage: /tmp/smc_enum [prefix]   (defaults to "CH")
 */

#include <stdio.h>
#include <string.h>
#include <IOKit/IOKitLib.h>
#include "SMCParamStruct.h"

static io_connect_t connect = IO_OBJECT_NULL;

#define MAX_INDEX 1000000
#define MISS_RUN_END 500

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

static void printKey(uint32_t key) {
    SMCParamStruct in = {0}, out = {0};
    in.key = key;
    in.data8 = kSMCGetKeyInfo;
    if (callSMC(&in, &out) != kSMCSuccess) {
        printf("%c%c%c%c: (key info failed result=%u)\n",
            (char)(key >> 24), (char)(key >> 16), (char)(key >> 8),
            (char)(key), out.result);
        return;
    }

    printf("%c%c%c%c: size=%u type=%c%c%c%c attr=0x%x\n",
        (char)(key >> 24), (char)(key >> 16), (char)(key >> 8), (char)(key),
        out.keyInfo.dataSize,
        (char)(out.keyInfo.dataType >> 24), (char)(out.keyInfo.dataType >> 16),
        (char)(out.keyInfo.dataType >> 8), (char)(out.keyInfo.dataType),
        out.keyInfo.dataAttributes);
}

int main(int argc, char **argv) {
    setvbuf(stdout, NULL, _IOLBF, 0);

    const char *prefix = argc > 1 ? argv[1] : "CH";
    size_t prefixLen = strlen(prefix);
    if (prefixLen == 0 || prefixLen > 4) {
        printf("prefix must be 1-4 characters\n");
        return 1;
    }

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

    unsigned misses = 0;
    for (uint32_t i = 0; i < MAX_INDEX && misses < MISS_RUN_END; i++) {
        SMCParamStruct in = {0}, out = {0};
        in.data8 = kSMCGetKeyFromIndex;
        in.data32 = i;
        if (callSMC(&in, &out) != kSMCSuccess) {
            misses++;
            continue;
        }
        misses = 0;

        char name[5] = {0};
        name[0] = (char)(out.key >> 24);
        name[1] = (char)(out.key >> 16);
        name[2] = (char)(out.key >> 8);
        name[3] = (char)(out.key);
        if (strncmp(name, prefix, prefixLen) == 0) {
            printKey(out.key);
        }
    }
    return 0;
}