/// Batch 2 — pure, deterministic intent classification for typed chat lines.
///
/// Only ADVICE vs REFINE are decided from text; SWITCH_ATMOSPHERE is triggered
/// by tapping an atmosphere, never by classifying text.
library;

import 'pwa_models.dart';

/// Words that signal the user is asking for an opinion (→ advice, text only).
const List<String> _adviceMarkers = [
  'what do you think',
  'what do you',
  'your opinion',
  'opinion',
  'should i',
  'do you think',
  'thoughts',
  'is it',
  'does it',
  'how does',
  'which',
];

/// Classify a typed chat line as advice (opinion, text-only, no version) or
/// refine (a visual change request that can create a child vision).
///
/// Heuristic: a question / opinion phrasing → advice; otherwise an instruction
/// → refine. Defaults to advice (the safe, non-version-creating branch).
PwaIntent classifyTextIntent(String raw) {
  final t = raw.trim().toLowerCase();
  if (t.isEmpty) return PwaIntent.advice;
  for (final m in _adviceMarkers) {
    if (t.contains(m)) return PwaIntent.advice;
  }
  // A trailing question mark with no imperative verb reads as an opinion ask.
  const refineVerbs = [
    'make', 'add', 'remove', 'open', 'change', 'more', 'less', 'brighter',
    'warmer', 'cooler', 'darker', 'lighter', 'replace', 'swap', 'declutter',
    'clean', 'move', 'bigger', 'smaller', 'soften', 'modern', 'cozy', 'cozier',
  ];
  final hasRefineVerb = refineVerbs.any((v) => t.contains(v));
  if (hasRefineVerb) return PwaIntent.refine;
  if (t.endsWith('?')) return PwaIntent.advice;
  // Fallback: treat a plain statement as a refine request only if it is short
  // and imperative-looking; otherwise advice.
  return PwaIntent.advice;
}
