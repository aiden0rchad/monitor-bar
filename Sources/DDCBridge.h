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
    DDCStatus status;
    int32_t ioReturn;
    uint8_t type;
    uint16_t maximum;
    uint16_t current;
} DDCValue;

/* Calls are synchronous; the caller must serialize them off the main thread.
 * Enumerate/Open/CopyEDID are read-only. GetVCP/Capabilities send only read requests.
 * Enumerate returns the number written, or -1 if the API is unavailable. */
int DDCEnumerate(DDCDisplay *displays, size_t capacity);
DDCHandle *DDCOpen(uint64_t registryID);
void DDCClose(DDCHandle *handle);
size_t DDCCopyEDID(DDCHandle *handle, uint8_t *output, size_t capacity);
DDCValue DDCGetVCP(DDCHandle *handle, uint8_t code);
DDCStatus DDCCapabilities(DDCHandle *handle, char *output, size_t capacity);
/* Success means the transaction was sent, not that the monitor applied it. */
DDCStatus DDCSetVCP(DDCHandle *handle, uint8_t code, uint16_t value);
const char *DDCStatusName(DDCStatus status);

#endif
