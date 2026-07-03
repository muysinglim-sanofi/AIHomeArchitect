/// PR2b Slice 1 — how to interpret a /generate response.
///
/// PR2a's backend claim can return a NON-image body for a duplicate/concurrent
/// intent. This classifier is PURE so the branching is unit-testable in isolation
/// (the UI actions — attach+poll / failure UX / render — live in _generate).
enum GenerateResultKind {
  /// after_image_url present — normal success OR byte-identical replay → render.
  image,

  /// {status:"running"} (HTTP 202) — another process owns this intent → attach
  /// (loading + reconciliation poll), never re-POST.
  running,

  /// {status:"failed"|"failed_terminal"} — route to the failure UX.
  failed,
}

/// Classify a /generate result map. A present, non-empty `after_image_url` always
/// wins (success/replay); otherwise the `status` field decides. An unknown/absent
/// status with no image defaults to [GenerateResultKind.image] (the legacy path),
/// so only the explicit running/failed contracts diverge.
GenerateResultKind classifyGenerateResult(Map<String, dynamic> result) {
  final hasImage = ((result['after_image_url'] as String?) ?? '').isNotEmpty;
  if (hasImage) return GenerateResultKind.image;
  final status = (result['status'] as String?) ?? '';
  if (status == 'running') return GenerateResultKind.running;
  if (status == 'failed' || status == 'failed_terminal') {
    return GenerateResultKind.failed;
  }
  return GenerateResultKind.image;
}
