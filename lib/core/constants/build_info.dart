/// Frontend build tag — a hardcoded marker to POSITIVELY identify which code is
/// running on a device. TestFlight does not tell you the git commit, so when we
/// need to confirm "is the phone actually on the latest build?", we read this
/// string on the Profile screen. If it matches what's committed, the device is
/// running this code — no ambiguity.
///
/// BUMP this string whenever you cut a build you want to identify.
const String kBuildTag = 'GI · homepage-derive · 2026-07-01d';
