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

#ifdef DDC_BRIDGE_TEST
static CFStringRef preferencesDomain;
#else
static const CFStringRef preferencesDomain = CFSTR("local.monitorbar.app");
#endif

/* Shared with the app and CLI. Check before discovery as well as I2C: even a
 * GetVCP request writes packets, and EDID discovery opens external services. */
static bool commandsPaused(void) {
    if (!preferencesDomain) return false;
    if (!CFPreferencesAppSynchronize(preferencesDomain)) return true;
    CFTypeRef value = CFPreferencesCopyAppValue(CFSTR("hardwareCommandsPaused"), preferencesDomain);
    if (!value) return false;
    bool paused = CFGetTypeID(value) != CFBooleanGetTypeID() || CFBooleanGetValue(value);
    CFRelease(value);
    return paused;
}

struct DDCHandle {
    CFTypeRef service;
    int profile; /* Read offset and checksum convention learned from valid replies. */
    uint64_t registryID;
    bool guarded;
    DDCHDMIConnection connection;
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
    if (commandsPaused()) return false;
    pthread_once(&loadOnce, loadAPI);
    return createService && copyEDID && readI2C && writeI2C;
}

static bool isExternal(io_service_t service) {
    CFTypeRef location = IORegistryEntryCreateCFProperty(service, CFSTR("Location"), kCFAllocatorDefault, 0);
    bool external = location && CFGetTypeID(location) == CFStringGetTypeID() && CFEqual(location, CFSTR("External"));
    if (location) CFRelease(location);
    return external;
}

static bool validEDID(CFDataRef data) {
    if (!data || CFGetTypeID(data) != CFDataGetTypeID()) return false;
    CFIndex length = CFDataGetLength(data);
    const uint8_t header[] = {0, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0};
    if (length < 128 || length > 4096 || length % 128) return false;
    const uint8_t *bytes = CFDataGetBytePtr(data);
    if (memcmp(bytes, header, sizeof(header)) || length < ((CFIndex)bytes[126] + 1) * 128) return false;
    for (CFIndex block = 0; block < length; block += 128) {
        uint8_t sum = 0;
        for (CFIndex i = block; i < block + 128; i++) sum += bytes[i];
        if (sum) return false;
    }
    return true;
}

static bool copyPortState(io_service_t port, DDCHDMIConnection *output) {
    CFMutableDictionaryRef properties = NULL;
    if (IORegistryEntryCreateCFProperties(port, &properties, kCFAllocatorDefault, 0) != KERN_SUCCESS || !properties) return false;
    CFTypeRef active = CFDictionaryGetValue(properties, CFSTR("ConnectionActive"));
    CFTypeRef count = CFDictionaryGetValue(properties, CFSTR("ConnectionCount"));
    CFTypeRef uuid = CFDictionaryGetValue(properties, CFSTR("ConnectionUUID"));
    int64_t number = -1;
    bool valid = active && CFGetTypeID(active) == CFBooleanGetTypeID() && CFBooleanGetValue(active)
        && count && CFGetTypeID(count) == CFNumberGetTypeID()
        && CFNumberGetValue(count, kCFNumberSInt64Type, &number) && number >= 0
        && uuid && CFGetTypeID(uuid) == CFStringGetTypeID()
        && CFStringGetCString(uuid, output->connectionUUID, sizeof(output->connectionUUID), kCFStringEncodingUTF8);
    if (valid) {
        CFUUIDRef parsed = CFUUIDCreateFromString(kCFAllocatorDefault, uuid);
        valid = parsed != NULL;
        if (parsed) CFRelease(parsed);
    }
    if (valid) {
        output->connectionCount = (uint64_t)number;
        valid = IORegistryEntryGetRegistryEntryID(port, &output->portRegistryID) == KERN_SUCCESS && output->portRegistryID != 0;
    }
    CFRelease(properties);
    return valid;
}

static int copyCachedHDMIConnection(DDCHDMIConnection *output) {
    DDCHDMIConnection connection = {0};
    io_iterator_t iterator = IO_OBJECT_NULL;
    if (IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("DCPAVServiceProxy"), &iterator) != KERN_SUCCESS) return 0;
    int proxies = 0;
    io_service_t entry;
    bool valid = true;
    while ((entry = IOIteratorNext(iterator))) {
        if (isExternal(entry)) {
            proxies++;
            valid &= IORegistryEntryGetRegistryEntryID(entry, &connection.display.registryID) == KERN_SUCCESS;
            valid &= IORegistryEntryGetPath(entry, kIOServicePlane, connection.display.registryPath) == KERN_SUCCESS;
        }
        IOObjectRelease(entry);
    }
    IOObjectRelease(iterator);
    if (!valid || proxies != 1 || !connection.display.registryID) return 0;
    if (IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleHDMIPortController"), &iterator) != KERN_SUCCESS) return 0;
    int ports = 0;
    while ((entry = IOIteratorNext(iterator))) {
        io_name_t name = {0};
        CFTypeRef active = IORegistryEntryCreateCFProperty(entry, CFSTR("ConnectionActive"), kCFAllocatorDefault, 0);
        bool isActive = active && CFGetTypeID(active) == CFBooleanGetTypeID() && CFBooleanGetValue(active);
        if (active) CFRelease(active);
        if (IORegistryEntryGetName(entry, name) == KERN_SUCCESS && !strcmp(name, "Port-HDMI") && isActive) {
            ports++;
            valid &= copyPortState(entry, &connection);
            io_iterator_t children = IO_OBJECT_NULL;
            int edids = 0;
            if (IORegistryEntryGetChildIterator(entry, kIOServicePlane, &children) == KERN_SUCCESS) {
                io_service_t child;
                while ((child = IOIteratorNext(children))) {
                    io_name_t childName = {0};
                    if (IORegistryEntryGetName(child, childName) == KERN_SUCCESS && !strcmp(childName, "DisplayPort")
                        && IOObjectConformsTo(child, "IOPortTransportStateDisplayPort")) {
                        edids++;
                        CFDataRef data = IORegistryEntryCreateCFProperty(child, CFSTR("EDID"), kCFAllocatorDefault, 0);
                        if (validEDID(data)) {
                            connection.display.edidLength = (size_t)CFDataGetLength(data);
                            memcpy(connection.display.edid, CFDataGetBytePtr(data), connection.display.edidLength);
                        } else valid = false;
                        if (data) CFRelease(data);
                    }
                    IOObjectRelease(child);
                }
                IOObjectRelease(children);
            }
            DDCHDMIConnection after = {0};
            valid &= edids == 1 && copyPortState(entry, &after)
                && connection.portRegistryID == after.portRegistryID
                && connection.connectionCount == after.connectionCount
                && !strcmp(connection.connectionUUID, after.connectionUUID);
        }
        IOObjectRelease(entry);
    }
    IOObjectRelease(iterator);
    if (!valid || ports != 1) return 0;
    *output = connection;
    return 1;
}

#ifdef DDC_BRIDGE_TEST
static int (*cachedConnectionReader)(DDCHDMIConnection *);
#endif

int DDCCopyCachedHDMIConnection(DDCHDMIConnection *output) {
    if (!output) return 0;
    memset(output, 0, sizeof(*output));
#ifdef DDC_BRIDGE_TEST
    if (cachedConnectionReader) return cachedConnectionReader(output);
#endif
    return copyCachedHDMIConnection(output);
}

static bool sameHDMIConnection(const DDCHDMIConnection *a, const DDCHDMIConnection *b) {
    return a->display.registryID == b->display.registryID && a->portRegistryID == b->portRegistryID
        && a->connectionCount == b->connectionCount && !strcmp(a->connectionUUID, b->connectionUUID)
        && !strcmp(a->display.registryPath, b->display.registryPath)
        && a->display.edidLength == b->display.edidLength && a->display.edidLength <= sizeof(a->display.edid)
        && !memcmp(a->display.edid, b->display.edid, a->display.edidLength);
}

int DDCHDMIConnectionsMatch(const DDCHDMIConnection *a, const DDCHDMIConnection *b) {
    return a && b && sameHDMIConnection(a, b);
}

static void pauseChangedConnection(void) {
    CFPreferencesSetAppValue(CFSTR("hardwarePauseReason"),
        CFSTR("The HDMI connection changed or could not be validated. Hardware controls are paused; check the connection and explicitly resume to rescan."), preferencesDomain);
    CFPreferencesSetAppValue(CFSTR("hardwareCommandsPaused"), kCFBooleanTrue, preferencesDomain);
    CFPreferencesAppSynchronize(preferencesDomain);
}

int DDCGuardHDMIConnection(DDCHandle *handle, const DDCHDMIConnection *expected) {
    if (commandsPaused() || !handle || !expected) return 0;
    DDCHDMIConnection current;
    if (handle->registryID != expected->display.registryID || !DDCCopyCachedHDMIConnection(&current)
        || !sameHDMIConnection(expected, &current)) {
        pauseChangedConnection();
        return 0;
    }
    handle->connection = *expected;
    handle->guarded = true;
    return 1;
}

static bool connectionValid(DDCHandle *handle) {
    if (commandsPaused()) return false;
    if (!handle->guarded) return true;
    DDCHDMIConnection current;
    if (DDCCopyCachedHDMIConnection(&current) && sameHDMIConnection(&handle->connection, &current)) return true;
    pauseChangedConnection();
    return false;
}

static IOReturn guardedI2C(DDCHandle *handle, I2COperation operation, uint32_t offset, void *bytes, uint32_t length) {
    if (!connectionValid(handle)) return kIOReturnNotPermitted;
    IOReturn result = operation(handle->service, 0x37, offset, bytes, length);
    return connectionValid(handle) ? result : kIOReturnNotPermitted;
}

size_t DDCCopyEDID(DDCHandle *handle, uint8_t *output, size_t capacity) {
    if (commandsPaused() || !handle || !output || !capacity) return 0;
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
    handle->registryID = registryID;
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
    if (commandsPaused()) return kIOReturnNotPermitted;
    uint8_t packet[8] = {0};
    packet[0] = 0x80 | (uint8_t)length;
    memcpy(packet + 1, payload, length);
    packet[length + 1] = checksum((profile & 1) ? 0x6e : 0x6e ^ 0x51, packet, length + 1);
    usleep(20000);
    if (commandsPaused()) return kIOReturnNotPermitted;
    IOReturn result = guardedI2C(handle, writeI2C, 0x51, packet, (uint32_t)length + 2);
    if (result != kIOReturnSuccess) return result;
    usleep(50000);
    if (commandsPaused()) return kIOReturnNotPermitted;
    memset(reply, 0, replySize);
    return guardedI2C(handle, readI2C, (profile & 2) ? 0x51 : 0, reply, (uint32_t)replySize);
}

DDCValue DDCGetVCPOnce(DDCHandle *handle, uint8_t code, int profile) {
    DDCValue value = { .status = DDC_UNAVAILABLE };
    if (commandsPaused() || !handle || profile < 0 || profile > 3) return value;
    uint8_t payload[] = {0x01, code}, reply[11];
    IOReturn result = exchange(handle, payload, sizeof(payload), reply, sizeof(reply), profile);
    if (result == kIOReturnSuccess) value = parseVCP(reply, sizeof(reply), code);
    else value.status = commandsPaused() ? DDC_UNAVAILABLE : DDC_TRANSPORT;
    value.ioReturn = result;
    return value;
}

DDCValue DDCGetVCP(DDCHandle *handle, uint8_t code) {
    DDCValue value = { .status = DDC_UNAVAILABLE };
    if (commandsPaused() || !handle) return value;
    uint8_t payload[] = {0x01, code}, reply[11];
    bool sawNull = false;
    for (int attempt = 0; attempt < 8; attempt++) {
        if (commandsPaused()) { value.status = DDC_UNAVAILABLE; return value; }
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
    if (commandsPaused() || !handle) return DDC_UNAVAILABLE;
    if (capacity > 8192) capacity = 8192;
    size_t offset = 0;
    double deadline = monotonicSeconds() + 15;
    while (offset < capacity - 1 && monotonicSeconds() < deadline) {
        uint8_t payload[] = {0xf3, (uint8_t)(offset >> 8), (uint8_t)offset};
        uint8_t reply[38];
        size_t length = 0;
        DDCStatus status = DDC_MALFORMED;
        for (int attempt = 0; attempt < 8; attempt++) {
            if (commandsPaused()) return DDC_UNAVAILABLE;
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
    if (commandsPaused() || !handle) return DDC_UNAVAILABLE;
    uint8_t packet[] = {0x84, 0x03, code, (uint8_t)(value >> 8), (uint8_t)value, 0};
    packet[5] = checksum(0x6e ^ 0x51, packet, 5);
    usleep(50000);
    if (commandsPaused()) return DDC_UNAVAILABLE;
    IOReturn result = guardedI2C(handle, writeI2C, 0x51, packet, sizeof(packet));
    usleep(50000);
    if (commandsPaused()) return DDC_UNAVAILABLE;
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
static int testWrites, testReads, testEDIDReads;
static bool pauseAfterWrite;
static uint8_t lastPacket[8];
static uint32_t lastPacketLength;
static const uint8_t *testReply;
static uint32_t lastReadOffset;
static DDCHDMIConnection testConnection;
static int testCachedReads;
static bool testConnectionAvailable = true, changeAfterWrite, changeAfterRead;

static int testCachedConnection(DDCHDMIConnection *output) {
    testCachedReads++;
    if (!testConnectionAvailable) return 0;
    *output = testConnection;
    return 1;
}

static IOReturn testWrite(CFTypeRef service, uint32_t chip, uint32_t offset, void *bytes, uint32_t length) {
    (void)service;
    assert(chip == 0x37 && offset == 0x51 && length <= sizeof(lastPacket));
    memcpy(lastPacket, bytes, length);
    lastPacketLength = length;
    testWrites++;
    if (pauseAfterWrite) CFPreferencesSetAppValue(CFSTR("hardwareCommandsPaused"), kCFBooleanTrue, preferencesDomain);
    if (changeAfterWrite) testConnection.connectionCount++;
    return kIOReturnSuccess;
}

static IOReturn testRead(CFTypeRef service, uint32_t chip, uint32_t offset, void *bytes, uint32_t length) {
    (void)service;
    assert(chip == 0x37 && length == 11);
    lastReadOffset = offset;
    testReads++;
    if (changeAfterRead) testConnection.connectionCount++;
    if (testReply) {
        memcpy(bytes, testReply, length);
        return kIOReturnSuccess;
    }
    return kIOReturnError;
}

static IOReturn testEDID(CFTypeRef service, CFDataRef *data) {
    (void)service; (void)data;
    testEDIDReads++;
    return kIOReturnError;
}

static void connectionChecks(void) {
    cachedConnectionReader = testCachedConnection;
    pauseAfterWrite = false;
    DDCHDMIConnection expected = {
        .display = { .registryID = 101, .edidLength = 128, .registryPath = "IOService:/fixture" },
        .portRegistryID = 102, .connectionCount = 43,
        .connectionUUID = "00112233-4455-4677-8899-AABBCCDDEEFF"
    };
    DDCHandle handle = { .profile = -1, .registryID = 101 };
    uint8_t reply[] = {0x6e, 0x88, 0x02, 0, 0x10, 0, 0, 50, 0, 33, 0};
    reply[10] = checksum(0x50, reply, 10);
    testReply = reply;
    testCachedReads = testWrites = testReads = 0;
    assert(!DDCGuardHDMIConnection(&handle, &expected)); /* Already paused. */
    assert(testCachedReads == 0 && testWrites == 0 && testReads == 0);
    CFPreferencesSetAppValue(CFSTR("hardwareCommandsPaused"), kCFBooleanFalse, preferencesDomain);
    testConnection = expected;
    assert(DDCGuardHDMIConnection(&handle, &expected));
    testCachedReads = 0;
    assert(DDCGetVCPOnce(&handle, 0x10, 0).status == DDC_OK);
    assert(testCachedReads == 4 && testWrites == 1 && testReads == 1);
    testCachedReads = testWrites = testReads = 0;
    assert(DDCSetVCP(&handle, 0x10, 34) == DDC_OK);
    assert(testCachedReads == 2 && testWrites == 1 && testReads == 0);

    /* Each identity field independently prevents a request from reaching I2C. */
    for (int field = 0; field < 7; field++) {
        CFPreferencesSetAppValue(CFSTR("hardwareCommandsPaused"), kCFBooleanFalse, preferencesDomain);
        testConnection = expected;
        switch (field) {
            case 0: testConnection.display.registryID++; break;
            case 1: testConnection.portRegistryID++; break;
            case 2: testConnection.connectionCount++; break;
            case 3: testConnection.connectionUUID[0] = '6'; break;
            case 4: testConnection.display.registryPath[0] = 'X'; break;
            case 5: testConnection.display.edidLength--; break;
            case 6: testConnection.display.edid[10]++; break;
        }
        testWrites = testReads = 0;
        assert(DDCGetVCPOnce(&handle, 0x10, 0).status == DDC_UNAVAILABLE);
        assert(commandsPaused() && testWrites == 0 && testReads == 0);
        CFTypeRef reason = CFPreferencesCopyAppValue(CFSTR("hardwarePauseReason"), preferencesDomain);
        assert(reason && CFGetTypeID(reason) == CFStringGetTypeID());
        CFRelease(reason);
    }

    CFPreferencesSetAppValue(CFSTR("hardwareCommandsPaused"), kCFBooleanFalse, preferencesDomain);
    testConnection = expected;
    changeAfterWrite = true;
    assert(DDCGetVCPOnce(&handle, 0x10, 0).status == DDC_UNAVAILABLE);
    assert(commandsPaused() && testWrites == 1 && testReads == 0);
    changeAfterWrite = false;

    CFPreferencesSetAppValue(CFSTR("hardwareCommandsPaused"), kCFBooleanFalse, preferencesDomain);
    testConnection = expected;
    testWrites = testReads = 0;
    changeAfterRead = true;
    assert(DDCGetVCPOnce(&handle, 0x10, 0).status == DDC_UNAVAILABLE);
    assert(commandsPaused() && testWrites == 1 && testReads == 1);
    changeAfterRead = false;

    CFPreferencesSetAppValue(CFSTR("hardwareCommandsPaused"), kCFBooleanFalse, preferencesDomain);
    testConnectionAvailable = false;
    testWrites = testReads = 0;
    assert(DDCSetVCP(&handle, 0x10, 34) == DDC_UNAVAILABLE);
    assert(commandsPaused() && testWrites == 0 && testReads == 0);
    testConnectionAvailable = true;

    CFPreferencesSetAppValue(CFSTR("hardwareCommandsPaused"), kCFBooleanFalse, preferencesDomain);
    testConnection = expected;
    handle.registryID = 999;
    assert(!DDCGuardHDMIConnection(&handle, &expected) && commandsPaused());
    assert(testWrites == 0 && testReads == 0 && testEDIDReads == 0);
    CFPreferencesSetAppValue(CFSTR("hardwarePauseReason"), NULL, preferencesDomain);
    cachedConnectionReader = NULL;
    testReply = NULL;
    puts("HDMI guards validate every identity field before/after each I2C operation and persist a pause on change (cached stubs).");
}

static void safetyChecks(void) {
    CFUUIDRef uuid = CFUUIDCreate(NULL);
    preferencesDomain = CFUUIDCreateString(NULL, uuid);
    CFRelease(uuid);
    writeI2C = testWrite;
    readI2C = testRead;
    copyEDID = testEDID;
    DDCHandle handle = { .profile = -1 };
    uint8_t bytes[16];
    char caps[64];
    DDCDisplay display;

    assert(DDCSetVCP(&handle, 0x10, 50) == DDC_OK);
    const uint8_t expected[] = {0x84, 0x03, 0x10, 0x00, 0x32, 0x9a};
    assert(lastPacketLength == sizeof(expected) && !memcmp(lastPacket, expected, sizeof(expected)));

    CFPreferencesSetAppValue(CFSTR("hardwareCommandsPaused"), kCFBooleanTrue, preferencesDomain);
    assert(CFPreferencesAppSynchronize(preferencesDomain));
    assert(commandsPaused());
    assert(DDCEnumerate(&display, 1) == -1);
    assert(DDCOpen(1) == NULL);
    assert(DDCCopyEDID(&handle, bytes, sizeof(bytes)) == 0);
    assert(DDCGetVCP(&handle, 0x10).status == DDC_UNAVAILABLE);
    assert(DDCCapabilities(&handle, caps, sizeof(caps)) == DDC_UNAVAILABLE);
    assert(DDCSetVCP(&handle, 0x10, 25) == DDC_UNAVAILABLE);
    assert(testWrites == 1 && testReads == 0 && testEDIDReads == 0);

    CFPreferencesSetAppValue(CFSTR("hardwareCommandsPaused"), kCFBooleanFalse, preferencesDomain);
    pauseAfterWrite = true;
    assert(DDCGetVCP(&handle, 0x10).status == DDC_UNAVAILABLE);
    assert(testWrites == 2 && testReads == 0); /* Pause cuts off readback and retries. */
    CFPreferencesSetAppValue(CFSTR("hardwareCommandsPaused"), CFSTR("invalid"), preferencesDomain);
    assert(commandsPaused()); /* Malformed preference fails closed. */

    testWrites = testReads = 0;
    assert(DDCGetVCPOnce(&handle, 0x10, 0).status == DDC_UNAVAILABLE);
    assert(testWrites == 0 && testReads == 0);
    CFPreferencesSetAppValue(CFSTR("hardwareCommandsPaused"), kCFBooleanFalse, preferencesDomain);
    pauseAfterWrite = false;
    assert(DDCGetVCPOnce(NULL, 0x10, 0).status == DDC_UNAVAILABLE);
    assert(DDCGetVCPOnce(&handle, 0x10, -1).status == DDC_UNAVAILABLE);
    assert(DDCGetVCPOnce(&handle, 0x10, 4).status == DDC_UNAVAILABLE);
    assert(testWrites == 0 && testReads == 0);

    DDCValue once = DDCGetVCPOnce(&handle, 0x10, 0);
    assert(once.status == DDC_TRANSPORT && once.ioReturn == (int32_t)kIOReturnError);
    assert(testWrites == 1 && testReads == 1 && lastReadOffset == 0);
    const uint8_t getExpected[] = {0x82, 0x01, 0x10, 0xac};
    assert(lastPacketLength == sizeof(getExpected) && !memcmp(lastPacket, getExpected, sizeof(getExpected)));

    uint8_t validReply[] = {0x6e, 0x88, 0x02, 0, 0x10, 0, 0, 50, 0, 33, 0};
    validReply[10] = checksum(0x50, validReply, 10);
    testReply = validReply;
    once = DDCGetVCPOnce(&handle, 0x10, 0);
    assert(once.status == DDC_OK && once.ioReturn == 0 && once.current == 33 && once.maximum == 50);
    assert(testWrites == 2 && testReads == 2);
    validReply[10] ^= 1;
    assert(DDCGetVCPOnce(&handle, 0x10, 0).status == DDC_MALFORMED);
    assert(testWrites == 3 && testReads == 3); /* Invalid replies do not trigger retries either. */
    testReply = NULL;

    pauseAfterWrite = true;
    once = DDCGetVCPOnce(&handle, 0x10, 0);
    assert(once.status == DDC_UNAVAILABLE && once.ioReturn == (int32_t)kIOReturnNotPermitted);
    assert(testWrites == 4 && testReads == 3);
    assert(DDCGetVCPOnce(&handle, 0x10, 0).status == DDC_UNAVAILABLE);
    assert(testWrites == 4 && testReads == 3 && testEDIDReads == 0);
    connectionChecks();
    CFPreferencesSetAppValue(CFSTR("hardwareCommandsPaused"), NULL, preferencesDomain);
    assert(CFPreferencesAppSynchronize(preferencesDomain));
    CFRelease(preferencesDomain);
    preferencesDomain = NULL;
    puts("DDC pause blocks discovery, EDID, Get, capabilities, Set and retry traffic (stub transport).");
    puts("Single GetVCP validates replies and sends at most one request/read, respecting pause (stub transport).");
}

/* clang -DDDC_BRIDGE_TEST Sources/DDCBridge.c -framework IOKit -framework CoreFoundation -o /tmp/ddc-bridge-test && /tmp/ddc-bridge-test */
int main(void) {
    uint8_t edid[256] = {0, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0};
    edid[126] = 1;
    edid[127] = 5;
    CFDataRef data = CFDataCreate(NULL, edid, sizeof(edid));
    assert(validEDID(data));
    CFRelease(data);
    data = CFDataCreate(NULL, edid, 128);
    assert(!validEDID(data)); /* Advertised extension is missing. */
    CFRelease(data);
    edid[200] = 1;
    data = CFDataCreate(NULL, edid, sizeof(edid));
    assert(!validEDID(data)); /* Every cached block needs a valid checksum. */
    CFRelease(data);
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
    safetyChecks();
    puts("DDC packet validation checks passed (no hardware access).");
    return 0;
}
#endif
