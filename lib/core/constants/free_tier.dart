/// Wave 5.17d — Free-tier scope (Decision D1, locked 2026-05-30).
///
/// Mirrors `backend/free_tier.py`. Both sides MUST agree — the frontend
/// uses these constants to dim + lock out-of-scope cards in the UI, and
/// the backend uses the equivalent constants in /generate to ENFORCE
/// the same policy. The single source of truth check lives in
/// `backend/_wave_5_17b_validation.py::S9` which asserts that the
/// FREE_* lists are subsets of the full catalogue.
///
/// On drift between this file and `backend/free_tier.py` :
///   - Frontend ahead → user is shown an unlocked card that the
///     backend rejects. Recoverable (paywall opens on /generate 402)
///     but ugly.
///   - Backend ahead → user is shown a locked card they could have
///     used. Customer support churn.
/// Keep them in lockstep. Same wave, same commit, same review.
library;

/// Canonical room ids that free (non-premium) users can transform.
/// Mirrors `backend/free_tier.py::FREE_ROOMS`. Ids match the keys in
/// `frontend/lib/core/constants/room_type_images.dart`.
const Set<String> kFreeRoomIds = {
  'livingRoom',
};

/// Canonical atmosphere ids that free users can use. Mirrors
/// `backend/free_tier.py::FREE_ATMOSPHERES`. Ids match the `id` field
/// of `AtmosphereStyle` in `frontend/lib/core/models/atmosphere_style.dart`.
const Set<String> kFreeAtmosphereIds = {
  'nordic_warmth',
  'soft_luxury',
};

/// True iff the (room_id, atmosphere_id) pair is in the free scope.
/// Premium status is NOT considered here — the caller checks premium
/// FIRST (via `RevenuecatService.isPremium`) and only consults this
/// function when the user is on the free tier.
bool isFreeTierAllowed({
  required String? roomTypeId,
  required String? atmosphereId,
}) {
  if (roomTypeId == null || !kFreeRoomIds.contains(roomTypeId)) return false;
  if (atmosphereId == null || !kFreeAtmosphereIds.contains(atmosphereId)) {
    return false;
  }
  return true;
}
