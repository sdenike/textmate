// Applications/TextMate/src/TextMate-Bridging-Header.h
//
// The ONLY Objective-C surface Swift can see. Keep it this small.
//
// ClangImporter compiles this as C/Objective-C, never Objective-C++, and
// without GCC_PREFIX_HEADER. Adding an Xcode/include/<framework> header here
// fails with "unknown type name 'NSNotificationName'" and similar, because
// those headers take their AppKit imports from the prelude. Adding anything
// with C++ in it fails with "function definition declared 'typedef'".

#import <Cocoa/Cocoa.h>
#import "SetupAssistant/SetupAssistantTypes.h"
