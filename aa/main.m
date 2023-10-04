#include <math.h>
#include <signal.h>
#include <time.h>
#include <unistd.h>
#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include <AppKit/AppKit.h>
#include <AppKit/NSHapticFeedback.h>


// Function to perform haptic feedback
void performHapticFeedback(void) {
    [[NSHapticFeedbackManager defaultPerformer] performFeedbackPattern:NSHapticFeedbackPatternGeneric performanceTime:NSHapticFeedbackPerformanceTimeNow];
}

int accumul = 0;

// Function to check if the haptic feedback threshold is reached
void goBrr(int delta){
    accumul += abs(delta);
    if (accumul > 35) {
        accumul = 0;
        performHapticFeedback();
    }
}

typedef int CGSConnectionID;
CGError CGSSetConnectionProperty(CGSConnectionID cid, CGSConnectionID targetCID, CFStringRef key, CFTypeRef value);
int _CGSDefaultConnection(void);

typedef struct { float x, y; } mtPoint;
typedef struct { mtPoint pos, vel; } mtReadout;

// Finger structure to store finger-related information
typedef struct {
    int frame;
    double timestamp;
    int identifier, state, foo3, foo4;
    mtReadout normalized;
    float size;
    int zero1;
    float angle, majorAxis, minorAxis; // ellipsoid
    mtReadout mm;
    int zero2[2];
    float unk2;
} Finger;

typedef void *MTDeviceRef;
typedef int (*MTContactCallbackFunction)(int, Finger *, int, double, int);

MTDeviceRef MTDeviceCreateDefault(void);
void MTRegisterContactFrameCallback(MTDeviceRef, MTContactCallbackFunction);
void MTDeviceStart(MTDeviceRef, int);
void MTDeviceGetDeviceID(MTDeviceRef, int);

const int speed = 20;

static CGPoint freezePoint;
bool scrolling = false;

// Callback function to handle touch events
int callback(int device, Finger *data, int nFingers, double timestamp, int frame) {
    for (int i = 0; i < nFingers; i++) {
        Finger *f = &data[i];
//        printf("Frame %7d: Angle %6.2f, ellipse %6.3f x%6.3f; "
//               "position (%6.3f,%6.3f) vel (%6.3f,%6.3f) "
//               "ID %d, state %d [%d %d?] size %6.3f, %6.3f?\n",
//               f->frame,
//               f->angle * 90 / atan2(1,0),
//               f->majorAxis,
//               f->minorAxis,
//               f->normalized.pos.x,
//               f->normalized.pos.y,
//               f->normalized.vel.x,
//               f->normalized.vel.y,
//               f->identifier, f->state, f->foo3, f->foo4,
//               f->size, f->unk2);
        

        if (i == 0 && f->normalized.pos.x > 0.97 && f->normalized.pos.y > 0.1 && f->angle <= 95) {
            if (!scrolling) {
                CGEventRef event = CGEventCreate(NULL);
                CGPoint point = CGEventGetLocation(event);
                CFRelease(event);
                freezePoint = point;
                scrolling = true;
            }
            goBrr(f->normalized.vel.y * speed);

            // Move the cursor to the freeze point
            CGEventRef move = CGEventCreateMouseEvent(NULL, kCGEventMouseMoved,
                                                      freezePoint,
                                                      kCGMouseButtonLeft);
            CGEventPost(kCGSessionEventTap, move);
            CFRelease(move);

            // Scroll the content
            CGEventRef event3 = CGEventCreateScrollWheelEvent(NULL, kCGScrollEventUnitPixel, 2, (f->normalized.vel.y * speed), 0);
            CGEventPost(kCGHIDEventTap, event3);
            CFRelease(event3);
        } else {
            if (scrolling) {
                scrolling = false;
            }
        }
    }

    return 0;
}


// Add function prototypes
CFArrayRef MTDeviceCreateList(void);
void registerCallbackForDevice(MTDeviceRef device);
void handleDeviceChangeEvent(void);
void initializeAndMonitorDeviceChanges(void);

// Function to register the callback for each device
void registerCallbackForDevice(MTDeviceRef device) {
    MTRegisterContactFrameCallback(device, callback);
    MTDeviceStart(device, 0);
}



CFMutableArrayRef trackedDevices = NULL;

// Timer handler to periodically check for new devices
void timerHandler(int sig) {
    handleDeviceChangeEvent();
}

// Set up a timer to call the timerHandler function periodically
void setupTimer(unsigned interval) {
    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = &timerHandler;
    sigaction(SIGALRM, &sa, NULL);

    struct itimerval timer;
    timer.it_value.tv_sec = interval;
    timer.it_value.tv_usec = 0;
    timer.it_interval.tv_sec = interval;
    timer.it_interval.tv_usec = 0;

    setitimer(ITIMER_REAL, &timer, NULL);
}

void handleDeviceChangeEvent(void) {
    // Get the list of all devices
    CFArrayRef devices = MTDeviceCreateList();

    // Iterate through the list of devices
    for (int i = 0; i < CFArrayGetCount(devices); i++) {
        MTDeviceRef device = (MTDeviceRef)CFArrayGetValueAtIndex(devices, i);
        int deviceID = 0;
        MTDeviceGetDeviceID(device, deviceID);

        // Check if the deviceID is already in the tracked devices array
        if (trackedDevices == NULL || !CFArrayContainsValue(trackedDevices, CFRangeMake(0, CFArrayGetCount(trackedDevices)), (const void *)(uintptr_t)deviceID)) {
            // If not, add the deviceID to the tracked devices array
            if (trackedDevices == NULL) {
                trackedDevices = CFArrayCreateMutable(NULL, 0, NULL);
            }
            CFArrayAppendValue(trackedDevices, (const void *)(uintptr_t)deviceID);

            // Register the callback for the new device
            registerCallbackForDevice(device);
        }
    }

    // Remove disconnected devices from the tracked devices array
    if (trackedDevices != NULL) {
        CFIndex trackedCount = CFArrayGetCount(trackedDevices);
        for (CFIndex i = 0; i < trackedCount; i++) {
            int trackedDeviceID = (int)(uintptr_t)CFArrayGetValueAtIndex(trackedDevices, i);
            bool found = false;

            for (int j = 0; j < CFArrayGetCount(devices); j++) {
                MTDeviceRef device = (MTDeviceRef)CFArrayGetValueAtIndex(devices, j);
                int deviceID = 0;
                MTDeviceGetDeviceID(device, deviceID);
                if (deviceID == trackedDeviceID) {
                    found = true;
                    break;
                }
            }

            if (!found) {
                CFArrayRemoveValueAtIndex(trackedDevices, i);
                i--;
                trackedCount--;
            }
        }
    }

    // Release the devices list
    CFRelease(devices);
}

int main(void) {
    // Handle the initial set of devices
    handleDeviceChangeEvent();

    // Set up a timer to periodically check for new devices
    unsigned interval = 60; // Check for new devices every 5 seconds
    setupTimer(interval);

    printf("Ctrl-C to abort\n");
    while (1) {
        pause();
    }

    return 0;
}
