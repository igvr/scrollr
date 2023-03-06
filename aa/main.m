#include <math.h>
#include <unistd.h>
#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include <AppKit/AppKit.h>
#include <AppKit/NSHapticFeedback.h>

//NSHapticFeedbackPerformer* performer;

void performHapticFeedback(void) {
    [[NSHapticFeedbackManager defaultPerformer] performFeedbackPattern:NSHapticFeedbackPatternGeneric performanceTime:NSHapticFeedbackPerformanceTimeNow];
}

int accumul = 0;
void goBrr(int delta){
    accumul+=delta;
    if(accumul>5000){
        accumul=0;
        performHapticFeedback();
    }
}

typedef int CGSConnectionID;
CGError CGSSetConnectionProperty(CGSConnectionID cid, CGSConnectionID targetCID, CFStringRef key, CFTypeRef value);
int _CGSDefaultConnection(void);

typedef struct { float x,y; } mtPoint;
typedef struct { mtPoint pos,vel; } mtReadout;

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
typedef int (*MTContactCallbackFunction)(int,Finger*,int,double,int);

MTDeviceRef MTDeviceCreateDefault(void);
void MTRegisterContactFrameCallback(MTDeviceRef, MTContactCallbackFunction);
void MTDeviceStart(MTDeviceRef, int); // thanks comex

const int speed = 20;

static int previd = 0;
static CGPoint freezPoint;

int callback(int device, Finger *data, int nFingers, double timestamp, int frame) {
    for (int i=0; i<nFingers; i++) {
        
        Finger *f = &data[i];
        printf("Frame %7d: Angle %6.2f, ellipse %6.3f x%6.3f; "
               "position (%6.3f,%6.3f) vel (%6.3f,%6.3f) "
               "ID %d, state %d [%d %d?] size %6.3f, %6.3f?\n",
               f->frame,
               f->angle * 90 / atan2(1,0),
               f->majorAxis,
               f->minorAxis,
               f->normalized.pos.x,
               f->normalized.pos.y,
               f->normalized.vel.x,
               f->normalized.vel.y,
               f->identifier, f->state, f->foo3, f->foo4,
               f->size, f->unk2);
        
        
      
        
        if(i==0 && f->normalized.pos.x > 0.97 && f->normalized.pos.y > 0.1 && f->angle <= 95) {

//            CFStringRef propertyString = CFStringCreateWithCString(NULL, "SetsCursorInBackground", kCFStringEncodingMacRoman);
//            CGSSetConnectionProperty(_CGSDefaultConnection(), _CGSDefaultConnection(), propertyString, kCFBooleanTrue);
//            CFRelease(propertyString);
//            CGDisplayHideCursor(kCGDirectMainDisplay);

//            CGEventErr err;
            
            //Com_Printf("**** Calling CGAssociateMouseAndMouseCursorPosition(false)\n");
//            err = CGAssociateMouseAndMouseCursorPosition(false);
//            if (err == CGEventNoErr) {
//                NSLog(@"Could not disable mouse movement, CGAssociateMouseAndMouseCursorPosition returned %d\n", err);
//            }
            

            
            CGPoint point = freezPoint;
            point.x = point.x - (f->normalized.pos.x * speed);
            point.y = point.y - (f->normalized.pos.y * speed);

            // freez
            CGEventRef move = CGEventCreateMouseEvent(NULL, kCGEventMouseMoved,
                                                      point,
                                                      kCGMouseButtonLeft);
            
//            calculateDeltas(&move, point);
            goBrr(point.y);
            
            CGEventPost(kCGSessionEventTap, move);
            CFRelease(move);
            // scroll
//            CGEventRef event;
            CGEventRef event = CGEventCreate(NULL);
            event = CGEventCreateScrollWheelEvent(NULL, kCGScrollEventUnitPixel, 2, (f->normalized.vel.y * speed), 0);
            CGEventPost(kCGHIDEventTap, event);
            
            CFRelease(event);
        } else {
            CGEventRef event = CGEventCreate(NULL);
            
            
            CGPoint point = CGEventGetLocation(event);
            CFRelease(event);
            freezPoint = point;
        }
    }
    printf("\n");
    
    
    return 0;
}

int main() {
    MTDeviceRef dev = MTDeviceCreateDefault();
    MTRegisterContactFrameCallback(dev, callback);
    MTDeviceStart(dev, 0);
    printf("Ctrl-C to abort\n");
    sleep(-1);
    return 0;
}
