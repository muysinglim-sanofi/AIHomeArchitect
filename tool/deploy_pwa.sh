#!/usr/bin/env bash
# THE canonical PWA deploy. Use this, not `firebase deploy` and not a bare
# `firebase hosting:channel:deploy`.
#
#   ./tool/deploy_pwa.sh phase10-acceptance      # a preview channel
#   ./tool/deploy_pwa.sh --preprod               # preprod.aydenstudio.com
#   ./tool/deploy_pwa.sh --live                  # live staging (asks first)
#
# WHY THE GUARD IS HERE AND NOT IN firebase.json
#
# It was a `predeploy` hook first. That hook runs through the SYSTEM shell —
# cmd.exe on Windows — which does not resolve `node` even when the firebase CLI
# (itself node) runs fine from the same terminal. The hook therefore refused
# every deploy on the machine this product is built on, which is worse than no
# guard: a broken guard gets deleted, and then nothing checks.
#
# So the check lives in the documented command instead. `firebase.json` has no
# predeploy, and this script is what the runbook names.
set -euo pipefail
cd "$(dirname "$0")/.."

TARGET="${1:-}"
if [[ -z "$TARGET" ]]; then
  echo "usage: $0 <preview-channel> | --preprod | --live" >&2
  exit 2
fi

# 1. The bundle must be the PWA's, built by tool/build_pwa.sh.
node tool/verify_pwa_build.mjs

# 2. The shell must not be cached forever. This is the RELEASE-CRITICAL rule:
#    build/web is served under filenames that never change, so an immutable
#    year on any of them freezes every returning browser on that build.
node - <<'JS'
const fs = require('node:fs');
const cfg = JSON.parse(fs.readFileSync('firebase.json', 'utf8'));
const SHELL = ['/', '/index.html', '/main.dart.js', '/flutter_bootstrap.js',
               '/flutter.js', '/version.json', '/manifest.json',
               '/flutter_service_worker.js'];
// `hosting` became an ARRAY the day preprod got its own site, and EVERY
// target must satisfy this rule — a guard that read only the first one
// would wave through a preprod config that freezes browsers. Both shapes
// are accepted, so a config rewrite cannot silently skip the check.
const targets = Array.isArray(cfg.hosting) ? cfg.hosting : [cfg.hosting];
const bad = [];
for (const t of targets) {
  const name = t.target || 'default';
  const rules = t.headers || [];
  for (const path of SHELL) {
    const rule = rules.find((r) => r.source === path);
    const cc = rule && (rule.headers || []).find(
      (h) => h.key.toLowerCase() === 'cache-control');
    if (!cc) { bad.push(name + ' ' + path + ': no rule'); continue; }
    if (!/no-cache/.test(cc.value) || /immutable/.test(cc.value)) {
      bad.push(name + ' ' + path + ': ' + cc.value);
    }
  }
}
if (bad.length) {
  console.error('\nREFUSING TO DEPLOY: the app shell would be cached.\n  '
    + bad.join('\n  ') + '\n');
  process.exit(2);
}
console.log('==> cache guard: the shell revalidates on '
  + targets.length + ' target(s)');
JS

if [[ "$TARGET" == "--live" ]]; then
  echo ""
  echo "This deploys to LIVE staging (ayden-studio.web.app), replacing what"
  echo "everyone who has the link is running."
  read -r -p "Type the word live to continue: " ok
  [[ "$ok" == "live" ]] || { echo "aborted"; exit 1; }
  # `--only hosting` would deploy EVERY target, live and preprod together.
  # Named explicitly, so one command touches exactly one site.
  exec firebase deploy --only hosting:live
fi

if [[ "$TARGET" == "--preprod" ]]; then
  # The dedicated preproduction site (ayden-studio-preprod), behind
  # preprod.aydenstudio.com. It carries the SAME staging build as every
  # preview channel — same API, same Supabase project, same PayWay sandbox
  # — and keeps its own release history, so rolling it back never touches
  # live. No confirmation prompt: nothing public depends on it.
  echo "==> deploying to PREPROD (ayden-studio-preprod). Live is untouched."
  exec firebase deploy --only hosting:preprod
fi

exec firebase hosting:channel:deploy "$TARGET" --expires 30d
