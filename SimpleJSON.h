// SimpleJSON.h
// Minimal JSON parser for OS X 10.6 (NSJSONSerialization requires 10.7+)
// Returns NSDictionary, NSArray, NSString, NSNumber, or NSNull.
// Returns nil on any parse error.

#import <Foundation/Foundation.h>

id FNParseJSON(NSData *data, NSError **outError);
