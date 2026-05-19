# Known Limitations — AIHomeArchitect Backend

*Last updated: Wave 4.2.6 freeze (2026-05-16)*

---

## L1 — Architectural Identity Preservation (Deferred to Wave 4.3.0)

**Symptom:** Atmosphere transformations can override the structural identity of complex
spaces. Architectural anchors (columns, archways, ceiling vaults, mezzanines, unusual
floor plans) may be altered or replaced when a strong atmosphere DNA is applied.

**Root cause:** Preservation arbitration is currently heuristic-based. The structural
contract in the prompt (`CAMERA LOCK`, vanishing points) anchors camera angle and broad
geometry, but does not give the model explicit priority rules when atmosphere directives
conflict with structural preservation.

**Status:** Intentionally deferred. Do not attempt to fix in Waves 4.2.x.

**Planned resolution:** Wave 4.3.0 — Preservation Intelligence.
Expected work: explicit structural anchor detection, priority-weighted prompt
sections, and per-room topology preservation logic.

---

## L2 — DEV Quality vs. PROD Quality Gap (By Design)

**Symptom:** DEV mode generations (`quality=low`, `size=1024x1024`) show visibly lower
render fidelity than PROD (`quality=high`, aspect-ratio size). Textures, lighting
nuance, and material richness are reduced.

**Root cause:** This is the intended behavior of the DEV profile. DEV is designed for
fast, cheap iteration — not production-grade output.

**Status:** Accepted tradeoff. Not a bug.

**Action required:** Always switch `APP_ENV=prod` before user-facing demos or
production builds.

---

## L3 — Interior Completeness Rule Drops Under Budget Pressure (By Design)

**Symptom:** The interior completeness rule (P4, ~298 chars) may be omitted from
FIRST_VISION prompts when the source room description is long (100+ chars), because
the combined prompt approaches the 3250-char budget ceiling.

**Root cause:** P4 enrichments are the first to drop when budget fills. This is the
correct behavior of the priority budget system.

**Status:** Accepted tradeoff. The rule is present and injected on paths with
sufficient headroom (e.g., first generation with no prior room description).

**Action required:** None. The budget system is working correctly.

---

## L4 — Reconciliation Polling Terminates at 90s (By Design)

**Symptom:** If the backend takes longer than 90 seconds to complete generation after
a client transport timeout, the frontend gives up and shows the "took longer than
expected" message, even though the backend may still succeed.

**Root cause:** Reconciliation polling runs for 18 × 5s = 90s maximum. This is a
deliberate UX tradeoff: indefinite polling is worse than a clear user message.

**Status:** Accepted tradeoff. The backend image is still saved to Supabase and
the user can reload to see it.

**Potential improvement:** Surface a "check for new images" affordance in the UI.
Deferred to a future UX wave.

---

*Limitations marked "Deferred to Wave 4.3.0" will not be addressed in Waves 4.2.x.*
*Do not optimize around these limitations in the current wave.*
