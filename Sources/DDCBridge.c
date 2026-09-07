#include "DDCBridge.h"
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <dlfcn.h>
#include <limits.h>
#include <pthread.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

/* Private IOKit SPI declarations are documented by the original implementers:
 * https://notes.alinpanaitiu.com/Decoding-monitor-EDID-on-macOS
 * https://github.com/MonitorControl/MonitorControl/blob/main/MonitorControl/Support/Bridging-Header.h
 * Protocol reference: https://github.com/rockowitz/ddcutil/blob/master/src/base/ddc_packets.c
 * This bridge is independently implemented and does not copy their code. */
typedef CFTypeRef (*CreateService)(CFAllocatorRef, io_service_t);
typedef IOReturn (*CopyEDID)(CFTypeRef, CFDataRef *);
typedef IOReturn (*I2COperation)(CFTypeRef, uint32_t, uint32_t, void *, uint32_t);
static CreateService createService;
static CopyEDID copyEDID;
static I2COperation readI2C, writeI2C;
static pthread_once_t loadOnce = PTHREAD_ONCE_INIT;

struct DDCHandle {
    CFTypeRef service;
    int profile; /* Read offset and checksum convention learned from valid replies. */
};

static void loadAPI(void) {
    void *library = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY | RTLD_LOCAL);
    if (!library) return;
    createService = (CreateService)dlsym(library, "IOAVServiceCreateWithService");
    copyEDID = (CopyEDID)dlsym(library, "IOAVServiceCopyEDID");
    readI2C = (I2COperation)dlsym(library, "IOAVServiceReadI2C");
    writeI2C = (I2COperation)dlsym(library, "IOAVServiceWriteI2C");
}

static bool available(void) {
    pthread_once(&loadOnce, loadAPI);
    return createService && copyEDID && readI2C && writeI2C;
}

static bool isExternal(io_service_t service) {
    CFTypeRef location = IORegistryEntryCreateCFProperty(service, CFSTR("Location"), kCFAllocatorDefault, 0);
    bool external = location && CFGetTypeID(location) == CFStringGetTypeID() && CFEqual(location, CFSTR("External"));
    if (location) CFRelease(location);
    return external;
}

size_t DDCCopyEDID(DDCHandle *handle, uint8_t *output, size_t capacity) {
    if (!handle || !output || !capacity) return 0;
    CFDataRef data = NULL;
    IOReturn result = copyEDID(handle->service, &data);
    if (result != kIOReturnSuccess || !data) {
        if (data) CFRelease(data);
        return 0;
    }
    size_t length = CFGetTypeID(data) == CFDataGetTypeID() ? (size_t)CFDataGetLength(data) : 0;
    if (length > capacity) length = capacity;
    if (length) memcpy(output, CFDataGetBytePtr(data), length);
    CFRelease(data);
    return length;
}

DDCHandle *DDCOpen(uint64_t registryID) {
    if (!registryID || !available()) return NULL;
    io_service_t entry = IOServiceGetMatchingService(kIOMainPortDefault, IORegistryEntryIDMatching(registryID));
    if (!entry) return NULL;
    CFTypeRef service = NULL;
    if (IOObjectConformsTo(entry, "DCPAVServiceProxy") && isExternal(entry)) service = createService(kCFAllocatorDefault, entry);
    IOObjectRelease(entry);
    if (!service) return NULL;
    DDCHandle *handle = calloc(1, sizeof(*handle));
    if (!handle) { CFRelease(service); return NULL; }
    handle->service = service;
    handle->profile = -1;
    return handle;
}

void DDCClose(DDCHandle *handle) {
    if (!handle) return;
    CFRelease(handle->service);
    free(handle);
}

int DDCEnumerate(DDCDisplay *displays, size_t capacity) {
    if (!available()) return -1;
    if (!displays || !capacity) return 0;
    if (capacity > INT_MAX) capacity = INT_MAX;
    io_iterator_t iterator = IO_OBJECT_NULL;
    if (IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("DCPAVServiceProxy"), &iterator) != KERN_SUCCESS) return -1;
    int count = 0;
    io_service_t entry;
    while ((entry = IOIteratorNext(iterator))) {
        if (isExternal(entry)) {
            DDCDisplay *display = &displays[count];
            memset(display, 0, sizeof(*display));
            IORegistryEntryGetRegistryEntryID(entry, &display->registryID);
            io_string_t path = {0};
            if (IORegistryEntryGetPath(entry, kIOServicePlane, path) == KERN_SUCCESS) strlcpy(display->registryPath, path, sizeof(display->registryPath));
            DDCHandle *handle = DDCOpen(display->registryID);
            if (handle) {
                display->edidLength = DDCCopyEDID(handle, display->edid, sizeof(display->edid));
                DDCClose(handle);
            }
            count++;
        }
        IOObjectRelease(entry);
        if ((size_t)count == capacity) break;
    }
    IOObjectRelease(iterator);
    return count;
}

static uint8_t checksum(uint8_t seed, const uint8_t *bytes, size_t length) {
    for (size_t i = 0; i < length; i++) seed ^= bytes[i];
    return seed;
}

static DDCStatus validateReply(const uint8_t *reply, size_t capacity, size_t *payloadLength) {
    if (capacity < 3 || reply[0] != 0x6e || !(reply[1] & 0x80)) return DDC_MALFORMED;
    size_t length = reply[1] & 0x7f;
    if (length + 3 > capacity || checksum(0x50, reply, length + 3)) return DDC_MALFORMED;
    *payloadLength = length;
    return length ? DDC_OK : DDC_NO_REPLY;
}

static DDCValue parseVCP(const uint8_t *reply, size_t capacity, uint8_t code) {
    DDCValue value = { .status = DDC_MALFORMED };
    size_t length = 0;
    value.status = validateReply(reply, capacity, &length);
    if (value.status != DDC_OK) return value;
    if (length != 8 || reply[2] != 0x02 || reply[4] != code || reply[3] > 1 || reply[5] > 1) {
        value.status = DDC_MALFORMED;
        return value;
    }
    if (reply[3] == 1) { value.status = DDC_UNSUPPORTED; return value; }
    value.type = reply[5];
    value.maximum = ((uint16_t)reply[6] << 8) | reply[7];
    value.current = ((uint16_t)reply[8] << 8) | reply[9];
    return value;
}

/* IOAVService supplies 0x6e and 0x51 on the wire; neither belongs in packet[].
 * Some established Apple Silicon implementations omit 0x51 from GetVCP's
 * checksum. Try both conventions, caching only a fully validated response. */
static IOReturn exchange(DDCHandle *handle, const uint8_t *payload, size_t length,
                         uint8_t *reply, size_t replySize, int profile) {
    uint8_t packet[8] = {0};
    packet[0] = 0x80 | (uint8_t)length;
    memcpy(packet + 1, payload, length);
    packet[length + 1] = checksum((profile & 1) ? 0x6e : 0x6e ^ 0x51, packet, length + 1);
    usleep(20000);
    IOReturn result = writeI2C(handle->service, 0x37, 0x51, packet, (uint32_t)length + 2);
    if (result != kIOReturnSuccess) return result;
    usleep(50000);
    memset(reply, 0, replySize);
    return readI2C(handle->service, 0x37, (profile & 2) ? 0x51 : 0, reply, (uint32_t)replySize);
}

DDCValue DDCGetVCP(DDCHandle *handle, uint8_t code) {
    DDCValue value = { .status = DDC_UNAVAILABLE };
    if (!handle) return value;
    uint8_t payload[] = {0x01, code}, reply[11];
    bool sawNull = false;
    for (int attempt = 0; attempt < 8; attempt++) {
        int profile = handle->profile >= 0 ? handle->profile : attempt % 4;
        value.ioReturn = exchange(handle, payload, sizeof(payload), reply, sizeof(reply), profile);
        if (value.ioReturn != kIOReturnSuccess) value.status = DDC_TRANSPORT;
        else {
            value = parseVCP(reply, sizeof(reply), code);
            if (value.status == DDC_OK || value.status == DDC_UNSUPPORTED) {
                handle->profile = profile;
                return value;
            }
            sawNull |= value.status == DDC_NO_REPLY;
        }
        if (handle->profile >= 0 && attempt == 2) break;
    }
    if (sawNull) { value.status = DDC_NO_REPLY; value.ioReturn = 0; }
    return value;
}

static double monotonicSeconds(void) {
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    return now.tv_sec + now.tv_nsec / 1e9;
}

DDCStatus DDCCapabilities(DDCHandle *handle, char *output, size_t capacity) {
    if (!output || !capacity) return DDC_TRUNCATED;
    output[0] = '\0';
    if (!handle) return DDC_UNAVAILABLE;
    if (capacity > 8192) capacity = 8192;
    size_t offset = 0;
    double deadline = monotonicSeconds() + 15;
    while (offset < capacity - 1 && monotonicSeconds() < deadline) {
        uint8_t payload[] = {0xf3, (uint8_t)(offset >> 8), (uint8_t)offset};
        uint8_t reply[38];
        size_t length = 0;
        DDCStatus status = DDC_MALFORMED;
        for (int attempt = 0; attempt < 8; attempt++) {
            /* The capability request uses the standard source-inclusive checksum first. */
            int profile = attempt % 4;
            IOReturn result = exchange(handle, payload, sizeof(payload), reply, sizeof(reply), profile);
            status = result == kIOReturnSuccess ? validateReply(reply, sizeof(reply), &length) : DDC_TRANSPORT;
            if (status == DDC_OK && (length < 3 || reply[2] != 0xe3 || (((size_t)reply[3] << 8) | reply[4]) != offset)) status = DDC_MALFORMED;
            if (status == DDC_OK) break;
        }
        if (status != DDC_OK) return status;
        size_t fragmentLength = length - 3;
        if (!fragmentLength) return DDC_OK;
        for (size_t i = 0; i < fragmentLength; i++) {
            if (!reply[5 + i]) return DDC_OK;
            if (reply[5 + i] < 0x20 || reply[5 + i] > 0x7e) return DDC_MALFORMED;
            if (offset >= capacity - 1) return DDC_TRUNCATED;
            output[offset++] = (char)reply[5 + i];
            output[offset] = '\0';
        }
    }
    return DDC_TRUNCATED;
}

DDCStatus DDCSetVCP(DDCHandle *handle, uint8_t code, uint16_t value) {
    if (!handle) return DDC_UNAVAILABLE;
    uint8_t packet[] = {0x84, 0x03, code, (uint8_t)(value >> 8), (uint8_t)value, 0};
    packet[5] = checksum(0x6e ^ 0x51, packet, 5);
    usleep(50000);
    IOReturn result = writeI2C(handle->service, 0x37, 0x51, packet, sizeof(packet));
    usleep(50000);
    return result == kIOReturnSuccess ? DDC_OK : DDC_TRANSPORT;
}

const char *DDCStatusName(DDCStatus status) {
    switch (status) {
        case DDC_OK: return "ok";
        case DDC_UNSUPPORTED: return "unsupported";
        case DDC_TRANSPORT: return "transport error";
        case DDC_MALFORMED: return "invalid reply";
        case DDC_UNAVAILABLE: return "DDC unavailable";
        case DDC_TRUNCATED: return "incomplete capabilities";
        case DDC_NO_REPLY: return "no reply (monitor may be busy)";
    }
    return "unknown";
}

#ifdef DDC_BRIDGE_TEST
#include <assert.h>
#include <stdio.h>
/* clang -DDDC_BRIDGE_TEST Sources/DDCBridge.c -framework IOKit -framework CoreFoundation -o /tmp/ddc-bridge-test && /tmp/ddc-bridge-test */
int main(void) {
    uint8_t reply[] = {0x6e, 0x88, 0x02, 0, 0x10, 0, 1, 0, 0, 75, 0};
    reply[10] = checksum(0x50, reply, 10);
    DDCValue value = parseVCP(reply, sizeof(reply), 0x10);
    assert(value.status == DDC_OK && value.maximum == 256 && value.current == 75);
    assert(parseVCP(reply, sizeof(reply), 0x12).status == DDC_MALFORMED);
    assert(parseVCP(reply, 10, 0x10).status == DDC_MALFORMED);
    reply[10] ^= 1;
    assert(parseVCP(reply, sizeof(reply), 0x10).status == DDC_MALFORMED);
    reply[3] = 1;
    reply[10] = checksum(0x50, reply, 10);
    assert(parseVCP(reply, sizeof(reply), 0x10).status == DDC_UNSUPPORTED);
    uint8_t nullReply[] = {0x6e, 0x80, 0xbe};
    assert(parseVCP(nullReply, sizeof(nullReply), 0x10).status == DDC_NO_REPLY);
    uint8_t caps[] = {0x6e, 0x86, 0xe3, 0, 0, 'v', 'c', 'p', 0};
    caps[8] = checksum(0x50, caps, 8);
    size_t length = 0;
    assert(validateReply(caps, sizeof(caps), &length) == DDC_OK && length == 6);
    puts("DDC packet validation checks passed (no hardware access).");
    return 0;
}
#endif
