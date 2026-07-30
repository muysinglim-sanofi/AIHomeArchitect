/// Batch 2 — explicit, testable web-entry decision for the PWA prototype.
///
/// Web boots into the mocked PWA experience; iOS/Android keep the existing
/// route tree (initial '/splash') unchanged. Pure so the platform decision is
/// unit-testable without real platform services.
library;

const String kPwaRoutePath = '/pwa';
const String kMobileInitialLocation = '/splash';

/// The router's initial location for the running platform.
///   web → '/pwa' (prototype)   ·   iOS/Android → '/splash' (unchanged)
String initialLocationForPlatform(bool isWeb) =>
    isWeb ? kPwaRoutePath : kMobileInitialLocation;
