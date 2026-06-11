#import <Foundation/Foundation.h>

@class BundleSpec;

// Fetches bundle archives from GitHub via codeload.github.com, extracts
// them into a target directory, and resolves branch/tag refs to current
// SHAs via git's smart-HTTP ref advertisement (what `git ls-remote` uses).
// Neither endpoint counts against the api.github.com rate limit, whose
// 60-per-hour unauthenticated budget per IP was easily exhausted by the
// previous per-bundle REST calls — which then starved the software-update
// check as well (issue #26).
//
// Transport is plain HTTPS with no cryptographic verification beyond TLS.
// Trust is rooted in GitHub's certificate chain plus the user's decision
// to subscribe to a given url/ref pair.

// Result of a SHA resolution.
@interface BundleSHAResolution : NSObject
@property (nonatomic, readonly) NSString* sha;   // 40-char hex
@end

@interface BundleFetcher : NSObject

+ (instancetype)sharedInstance;

// Parse https://github.com/owner/repo[.tmbundle] into owner/repo. Returns
// NO on malformed URLs. Exposed for tests and the fetcher's internal use.
+ (BOOL)parseURL:(NSString*)url owner:(NSString**)owner repo:(NSString**)repo;

// GET {repo}.git/info/refs?service=git-upload-pack and resolve spec.ref
// (branch, tag, fully qualified ref, or HEAD) to a commit SHA.
// Completion fires on the main queue.
- (void)resolveSHAForSpec:(BundleSpec*)spec
               completion:(void(^)(BundleSHAResolution* resolution, NSError* error))completion;

// Download codeload tarball for spec.url @ spec.ref, stream through tar,
// validate the resulting directory contains a matching info.plist, and
// atomically swap it into destURL. Fills spec.installedSHA / installedAt
// on success. Completion fires on the main queue.
- (void)fetchAndInstallSpec:(BundleSpec*)spec
                  intoURL:(NSURL*)destURL
                completion:(void(^)(NSString* installedSHA, NSError* error))completion;

@end
