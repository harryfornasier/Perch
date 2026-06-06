// FrigateAPI.h
// Async networking layer for Frigate NVR.
// All completion blocks are called on the main queue.

#import <Cocoa/Cocoa.h>

// Completion block types
typedef void (^FNArrayBlock)(NSArray *items, NSError *error);
typedef void (^FNImageBlock)(NSImage *image, NSError *error);

@interface FrigateAPI : NSObject {
    NSString *_baseURL;
}

@property (nonatomic, copy) NSString *baseURL;

+ (FrigateAPI *)sharedAPI;

// Returns sorted array of NSString camera names from /api/config
- (void)fetchCameraNames:(FNArrayBlock)completion;

// Returns NSImage of the latest JPEG frame for a camera
- (void)fetchLatestFrame:(NSString *)cameraName completion:(FNImageBlock)completion;

// Returns NSArray of NSDictionary events (all labels)
- (void)fetchEvents:(NSUInteger)limit completion:(FNArrayBlock)completion;

// Returns NSArray of NSDictionary events (person only)
- (void)fetchPersonDetections:(NSUInteger)limit completion:(FNArrayBlock)completion;

// Returns NSArray of NSDictionary person events newer than a timestamp
- (void)fetchPersonEventsSince:(double)timestamp completion:(FNArrayBlock)completion;

// Returns NSImage thumbnail for an event ID
- (void)fetchThumbnail:(NSString *)eventId completion:(FNImageBlock)completion;

// Returns the clip URL for an event (open with NSWorkspace)
- (NSURL *)clipURLForEvent:(NSString *)eventId;

// Returns the web UI URL for an event
- (NSURL *)webURLForEvent:(NSString *)eventId;

@end
