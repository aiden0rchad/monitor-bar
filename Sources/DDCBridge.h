#ifndef DDC_BRIDGE_H
#define DDC_BRIDGE_H

#include <stddef.h>
#include <stdint.h>

typedef struct DDCHandle DDCHandle;
typedef enum {
    DDC_OK = 0,
    DDC_UNSUPPORTED = 1,
    DDC_TRANSPORT = 2,
    DDC_MALFORMED = 3,
    DDC_UNAVAILABLE = 4,
    DDC_TRUNCATED = 5,
    DDC_NO_REPLY = 6
} DDCStatus;

typedef struct {
    uint64_t registryID;
    uint8_t edid[4096];
    size_t edidLength;
    char registryPath[1024];
} DDCDisplay;

typedef struct {
    DDCDisplay display;
    uint64_t portRegistryID;
    uint64_t connectionCount;
    char connectionUUID[128];
} DDCHDMIConnection;

typedef struct {
    DDCStatus status;
    int32_t ioReturn;
    uint8_t type;
    uint16_t maximum;
    uint16_t current;
} DDCValue;

/* Calls are synchronous; the caller must serialize them off the main thread.
 * Enumerate/Open/CopyEDID can contact the display; GetVCP/Capabilities write
 * request packets. Enumerate returns the number written, or -1 if unavailable. */
int DDCEnumerate(DDCDisplay *displays, size_t capacity);
/* Cached IORegistry properties only: no IOAV service creation or monitor traffic.
 * Returns 1 only for one active HDMI connection and one external DCP proxy. */
int DDCCopyCachedHDMIConnection(DDCHDMIConnection *output);
/* Compare cached identities without registry or hardware access. */
int DDCHDMIConnectionsMatch(const DDCHDMIConnection *a, const DDCHDMIConnection *b);
DDCHandle *DDCOpen(uint64_t registryID);
/* Attach the validated connection identity. Every subsequent I2C operation
 * checks it before and after; any change persistently pauses hardware commands. */
int DDCGuardHDMIConnection(DDCHandle *handle, const DDCHDMIConnection *expected);
void DDCClose(DDCHandle *handle);
size_t DDCCopyEDID(DDCHandle *handle, uint8_t *output, size_t capacity);
DDCValue DDCGetVCP(DDCHandle *handle, uint8_t code);
/* At most one request and one reply, without retries. Profiles 0...3 only:
 * bit 0 omits 0x51 from the request checksum; bit 1 reads at 0x51 instead of 0. */
DDCValue DDCGetVCPOnce(DDCHandle *handle, uint8_t code, int profile);
DDCStatus DDCCapabilities(DDCHandle *handle, char *output, size_t capacity);
/* Success means the transaction was sent, not that the monitor applied it. */
DDCStatus DDCSetVCP(DDCHandle *handle, uint8_t code, uint16_t value);
const char *DDCStatusName(DDCStatus status);

#endif
