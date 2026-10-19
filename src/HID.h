#import <CoreFoundation/CoreFoundation.h>

// Private IOKit HID API (current signatures; Theos' IOKit/hid headers are iOS 5-era).
typedef struct __IOHIDEvent *IOHIDEventRef;
typedef struct __IOHIDEventSystemClient *IOHIDEventSystemClientRef;
IOHIDEventSystemClientRef IOHIDEventSystemClientCreate(CFAllocatorRef allocator);
void IOHIDEventSystemClientDispatchEvent(IOHIDEventSystemClientRef client, IOHIDEventRef event);
typedef void (*IOHIDEventCallback)(void *target, void *refcon, void *sender, IOHIDEventRef event);
void IOHIDEventSystemClientRegisterEventCallback(IOHIDEventSystemClientRef client, IOHIDEventCallback cb,
                                                 void *target, void *refcon);
void IOHIDEventSystemClientUnregisterEventCallback(IOHIDEventSystemClientRef client);
void IOHIDEventSystemClientScheduleWithRunLoop(IOHIDEventSystemClientRef client, CFRunLoopRef rl, CFStringRef mode);
void IOHIDEventSystemClientUnscheduleWithRunLoop(IOHIDEventSystemClientRef client, CFRunLoopRef rl, CFStringRef mode);
IOHIDEventRef IOHIDEventCreateDigitizerEvent(CFAllocatorRef allocator, uint64_t timeStamp, uint32_t transducerType,
                                             uint32_t index, uint32_t identity, uint32_t eventMask, uint32_t buttonMask,
                                             double x, double y, double z, double tipPressure, double barrelPressure,
                                             Boolean range, Boolean touch, uint32_t options);
IOHIDEventRef IOHIDEventCreateDigitizerFingerEvent(CFAllocatorRef allocator, uint64_t timeStamp, uint32_t index,
                                                   uint32_t identity, uint32_t eventMask, double x, double y, double z,
                                                   double tipPressure, double twist, Boolean range, Boolean touch,
                                                   uint32_t options);
void IOHIDEventAppendEvent(IOHIDEventRef event, IOHIDEventRef child, uint32_t options);
void IOHIDEventSetIntegerValue(IOHIDEventRef event, uint32_t field, int value);
int IOHIDEventGetIntegerValue(IOHIDEventRef event, uint32_t field);
uint32_t IOHIDEventGetType(IOHIDEventRef event);
uint64_t IOHIDEventGetSenderID(IOHIDEventRef event);
void IOHIDEventSetSenderID(IOHIDEventRef event, uint64_t senderID);
IOHIDEventRef IOHIDEventCreateKeyboardEvent(CFAllocatorRef allocator, uint64_t timeStamp, uint32_t usagePage,
                                            uint32_t usage, Boolean down, uint32_t options);
