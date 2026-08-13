#import <Foundation/Foundation.h>

// NSUserDefaults is implicitly keyed on CFBundleIdentifier. Phase 4 changes
// TextMate's identifier from com.macromates.TextMate to
// com.shelbydenike.TextMate; the instant that happens, every setting the
// user has -- theme, font, window layout, file browser state, recent
// documents -- would silently revert to defaults unless migrated first.
//
// This ships in its own release BEFORE the identifier changes, so it has
// already run against the real old domain on a real machine before anything
// depends on it. Until Task 2 changes CFBundleIdentifier, this process's own
// domain IS com.macromates.TextMate, so MigrateLegacyPreferencesIfNeeded()
// migrates that domain into itself -- a deliberate no-op, not dead code.

// Marker key written into the destination domain once migration has run
// (whether it copied anything or legitimately had nothing to do), so a
// later launch can skip straight past the work.
extern NSString* const kUserDefaultsMigratedFromMacromatesKey;

// The domain TextMate's preferences lived under before the Phase 4 rename.
// Hardcoded because it names a specific historical identifier, not this
// build's own identity -- changing CFBundleIdentifier itself is Task 2.
extern NSString* const kLegacyPreferencesDomain;

// Copies every key persisted under sourceDomain into destinationDomain that
// destinationDomain does not already have, then marks destinationDomain as
// migrated. Never overwrites a key already present in destinationDomain. A
// source domain with nothing persisted (fresh install) is a normal no-op.
// Does not touch or delete sourceDomain, so the install can be rolled back.
// Safe to call with sourceDomain == destinationDomain -- today's state,
// before CFBundleIdentifier changes -- which copies nothing new and only
// adds the marker to that one shared domain.
void MigratePreferencesDomain (NSString* sourceDomain, NSString* destinationDomain);

// Real entry point: migrates kLegacyPreferencesDomain into this process's
// current bundle identifier. Call once, early in launch, before anything
// reads NSUserDefaults.standardUserDefaults -- a default read before this
// runs sees the unmigrated value.
void MigrateLegacyPreferencesIfNeeded (void);
