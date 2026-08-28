// The deploy guard.
//
// `firebase.json` publishes `build/web` — which is also exactly where a plain
// `flutter build web` writes the MOBILE entrypoint. The build script refuses
// to build the wrong thing; nothing refused to DEPLOY it. This does, from
// firebase.json's own `predeploy` hook, so the documented workflow cannot ship
// a bundle that `tool/build_pwa.sh` did not produce.
//
// The marker is written by that script and by nothing else. It carries no
// secret: an entrypoint path, a mode, and when it was built.
import fs from 'node:fs';

const MARKER = 'build/web/ayden-build.json';
const EXPECTED_ENTRY = 'lib/main_pwa.dart';

function refuse(why) {
  console.error('');
  console.error('REFUSING TO DEPLOY: ' + why);
  console.error('');
  console.error('  build/web must come from the canonical PWA build:');
  console.error('    ./tool/build_pwa.sh staging     (public staging)');
  console.error('    ./tool/build_pwa.sh mock        (offline demo)');
  console.error('');
  console.error('  A plain `flutter build web` builds lib/main.dart — the');
  console.error('  MOBILE entrypoint — into the same directory. It compiles,');
  console.error('  it looks plausible, and it has been deployed by mistake');
  console.error('  on this branch before.');
  console.error('');
  process.exit(2);
}

if (!fs.existsSync(MARKER)) {
  refuse('build/web carries no Ayden build marker.');
}

let marker;
try {
  marker = JSON.parse(fs.readFileSync(MARKER, 'utf8'));
} catch (e) {
  refuse('the build marker is unreadable (' + e.message + ').');
}

if (marker.entrypoint !== EXPECTED_ENTRY) {
  refuse('the bundle was built from ' + marker.entrypoint + ', not ' + EXPECTED_ENTRY + '.');
}
if (marker.mode !== 'staging' && marker.mode !== 'mock') {
  refuse('unknown build mode ' + marker.mode + '.');
}

// A marker older than the bundle means someone rebuilt over it by hand.
const shell = 'build/web/main.dart.js';
if (fs.existsSync(shell)) {
  const built = fs.statSync(MARKER).mtimeMs;
  const bundled = fs.statSync(shell).mtimeMs;
  if (bundled > built + 5000) {
    refuse('build/web/main.dart.js is newer than the build marker — the '
      + 'bundle was rebuilt outside tool/build_pwa.sh.');
  }
}

console.log('==> deploy guard: ' + marker.mode + ' build from ' + marker.entrypoint + ', ' + marker.builtAt);
