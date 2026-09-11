// The deploy guard.
//
// `firebase.json` publishes `build/web` — which is also exactly where a plain
// `flutter build web` writes the MOBILE entrypoint. The build script refuses
// to build the wrong thing; nothing refused to DEPLOY it. This does, from
// `tool/deploy_pwa.sh`, so the documented workflow cannot ship a bundle that
// `tool/build_pwa.sh` did not produce — nor ship it to the wrong site.
//
//   node tool/verify_pwa_build.mjs <--live | --preprod | preview-channel>
//
// WHICH BUILD MAY GO WHERE
//   production  ONLY to --live (site ayden-studio: app.aydenstudio.com/kh).
//               A production bundle on preprod or a preview channel would put
//               real money and real accounts behind an unreviewed address.
//   staging     preprod and preview channels, NEVER --live: live is production.
//   mock        preview channels only.
//
// The marker is written by that script and by nothing else. It carries no
// secret: an entrypoint path, a mode, addresses, and when it was built.
import fs from 'node:fs';

const MARKER = 'build/web/ayden-build.json';
const EXPECTED_ENTRY = 'lib/main_pwa.dart';
const TARGET = process.argv[2] || '';

const PROD = {
  supabaseProjectRef: 'vtxkciupyafukhdsgxgw',
  apiOrigin: 'https://api.aydenstudio.com',
  apiPrefix: '/pwa',
  routePrefix: '/kh',
};

function refuse(why) {
  console.error('');
  console.error('REFUSING TO DEPLOY: ' + why);
  console.error('');
  console.error('  build/web must come from the canonical PWA build:');
  console.error('    ./tool/build_pwa.sh production  (live: app.aydenstudio.com/kh)');
  console.error('    ./tool/build_pwa.sh staging     (preprod, preview channels)');
  console.error('    ./tool/build_pwa.sh mock        (offline demo, preview channels)');
  console.error('');
  console.error('  A plain `flutter build web` builds lib/main.dart — the');
  console.error('  MOBILE entrypoint — into the same directory. It compiles,');
  console.error('  it looks plausible, and it has been deployed by mistake');
  console.error('  on this branch before.');
  console.error('');
  process.exit(2);
}

if (!TARGET) {
  refuse('no deploy target given (--live, --preprod or a preview channel).');
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
if (!['production', 'staging', 'mock'].includes(marker.mode)) {
  refuse('unknown build mode ' + marker.mode + '.');
}

const live = TARGET === '--live';
if (marker.mode === 'production') {
  if (!live) {
    refuse('a PRODUCTION build may only be deployed with --live (got ' + TARGET + ').');
  }
  for (const [k, v] of Object.entries(PROD)) {
    if (marker[k] !== v) {
      refuse('the production marker says ' + k + '=' + marker[k] + ', expected ' + v + '.');
    }
  }
  // The marker says what the script MEANT; the bundle says what the compiler
  // GOT. On Git Bash the prefix once arrived as "C:/Program Files/Git/kh".
  const js = fs.existsSync('build/web/main.dart.js')
    ? fs.readFileSync('build/web/main.dart.js', 'utf8') : '';
  if (!js.includes('("' + PROD.routePrefix + '")') || /[A-Z]:\/Program Files\//.test(js)) {
    refuse('the compiled route prefix is not exactly "' + PROD.routePrefix
      + '" (a shell rewrote the define?). Rebuild with tool/build_pwa.sh.');
  }
} else if (live) {
  refuse('live is PRODUCTION (app.aydenstudio.com/kh); a ' + marker.mode
    + ' build may not replace it.');
} else if (marker.mode === 'mock' && TARGET === '--preprod') {
  refuse('preprod runs the staging build, not the offline mock.');
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

console.log('==> deploy guard: ' + marker.mode + ' build from ' + marker.entrypoint
  + ', ' + marker.builtAt + ' -> ' + TARGET);
