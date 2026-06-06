// AppDelegate.h
// Main application delegate. Owns the window and all UI.
// Acts as NSTableViewDataSource + NSTableViewDelegate for all three tables.

#import <Cocoa/Cocoa.h>

@interface AppDelegate : NSObject <NSApplicationDelegate,
                                    NSTableViewDataSource,
                                    NSTableViewDelegate,
                                    NSWindowDelegate>
{
    // -- Window / chrome -------------------------------------------------------
    NSWindow        *_window;
    NSTabView       *_tabView;
    NSTextField     *_statusField;
    NSTextField     *_connField;

    // -- Live tab --------------------------------------------------------------
    NSTableView     *_cameraTable;
    NSImageView     *_liveImageView;
    NSTextField     *_liveCamLabel;
    NSTextField     *_liveTimeLabel;
    NSTimer         *_liveTimer;
    NSArray         *_cameras;          // NSString
    NSInteger        _selectedCamera;

    // -- Events tab ------------------------------------------------------------
    NSTableView     *_eventsTable;
    NSImageView     *_thumbView;
    NSTextField     *_thumbPlaceholder;
    NSButton        *_playClipBtn;
    NSButton        *_browserBtn;
    NSArray         *_events;           // NSDictionary
    NSString        *_selectedEventId;

    // -- Detections tab --------------------------------------------------------
    NSTableView     *_detectionsTable;
    NSTextField     *_detCountField;
    NSArray         *_detections;       // NSDictionary

    // -- Notification state ----------------------------------------------------
    NSTimer         *_notifyTimer;
    double           _lastDetectionTS;  // Unix timestamp of newest seen event
    NSMutableSet    *_notifiedIds;      // event IDs we've already Growl'd

    // -- In-app clip player (QTKit) --------------------------------------------
    NSPanel         *_playerPanel;
    id               _movieView;        // QTMovieView -- typed as id to avoid
                                        // header dependency on QTKit

    // -- Preferences tab -------------------------------------------------------
    NSTextField     *_prefsURLField;    // editable URL text field
    NSTextField     *_prefsStatusField; // feedback label below the field
}
@end
