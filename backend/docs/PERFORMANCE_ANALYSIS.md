# AIHomeArchitect — Performance Analysis

**Version:** Wave 4.4.2  
**Purpose:** Latency, cost, and retry observability. Instrumentation baseline before any optimizations.

---

## Executive Summary

Wave 4.4.2 adds structured [PERF] logging throughout the /generate pipeline.  
No quality-impacting changes were made. All FROZEN systems are untouched.

**Observed PROD symptoms (pre-4.4.2):**
- Perceived latency: 90–150s typical, up to 2+ minutes on retry
- OpenAI attempt 1 fails after ~60s (timeout/RemoteProtocolError), retry triggers attempt 2
- Total cost: ~$0.60/render when attempt 2 is needed (2× image-edit cost + 2× vision cost)

---

## Pipeline Architecture

```
/generate request received
    │
    ├── image_fetch          (Supabase CDN download, ~1–5s)
    │
    ├── vision_analysis      (GPT-4o-mini detail=high, ~3–8s, NON-FATAL)
    │
    ├── prompt_composition   (local, CPU-only, ~5–50ms)
    │
    ├── mask_generation      (PIL draw + blur, run_in_executor, ~30–80ms)
    │
    ├── [PAYLOAD ESTIMATE]   (logged, not billed)
    │
    ├── openai_api           (gpt-image-1 images.edit, ~30–90s per attempt)
    │   └── retry loop (max_attempts=1 DEV, 3 PROD)
    │
    └── supabase_upload      (~1–3s)
```

---

## Stage Timing Reference

| Stage | Typical (ms) | Worst Case | Notes |
|-------|-------------|-----------|-------|
| image_fetch | 500–2000 | 5000 | Supabase CDN, depends on image size |
| vision_analysis | 3000–8000 | 15000 | GPT-4o-mini; non-fatal if fails |
| prompt_composition | 5–50 | 200 | Pure CPU, never the bottleneck |
| mask_generation | 30–80 | 200 | PIL C-level ops via run_in_executor |
| openai_api (×1) | 30000–90000 | 120000 | Dominant latency source |
| supabase_upload | 500–2000 | 5000 | Depends on generated image size |
| **TOTAL (1 attempt)** | **35–100s** | **140s** | |
| **TOTAL (2 attempts)** | **90–180s** | **300s** | Retry scenario |

---

## Cost Estimation Model

Cost estimates appear in [PERF SUMMARY] logs. **Not used for billing.**

| Quality | Size | Per Image (USD) |
|---------|------|----------------|
| high | 1536×1024 | $0.190 |
| high | 1024×1536 | $0.190 |
| high | 1024×1024 | $0.080 |
| medium | 1536×1024 | $0.070 |
| medium | 1024×1536 | $0.070 |
| medium | 1024×1024 | $0.040 |
| low | any | $0.020 |

**Vision analysis** (gpt-4o-mini detail=high): ~$0.004/call

**PROD single-attempt cost**: $0.190 (image) + $0.004 (vision) = **~$0.194**  
**PROD two-attempt cost**: $0.380 (2 images) + $0.008 (2 vision?) = **~$0.388**  
*(Note: vision is called once per request, not per OpenAI attempt.)*

Corrected two-attempt cost: $0.380 + $0.004 = **~$0.384**

---

## Log Format Reference

### Per-stage logs (emitted as each stage completes):
```
[PERF] stage=image_fetch      duration_ms=1240  size_bytes=892341
[PERF] stage=vision_analysis  duration_ms=4820
[PERF] stage=prompt_composition  duration_ms=12  chars=3241
[PERF] stage=mask_generation  duration_ms=67  mask_generated=True
[PERF] payload_estimate       total_bytes=1847822  image_bytes=892341  mask_bytes=954232  prompt_bytes=3249
[PERF] stage=supabase_upload  duration_ms=1830  size_bytes=1204800
```

### [PERF SUMMARY] (emitted at request end, always):
```
[PERF SUMMARY] request_id=abc123
  total_ms=67420
  fetch_ms=1240  vision_ms=4820  prompt_ms=12  mask_ms=67
  openai_ms=59800 (x1 attempts)  upload_ms=1830
  payload_bytes=1847822  prompt_chars=3241
  est_cost_usd=0.194  cost_risk=MEDIUM
```

### Cost risk tiers:
| Label | Range | Typical scenario |
|-------|-------|-----------------|
| LOW | < $0.05 | DEV mode (medium quality, 1024×1024) |
| MEDIUM | $0.05–$0.25 | PROD single attempt |
| HIGH | $0.25–$0.50 | PROD two attempts |
| CRITICAL | ≥ $0.50 | PROD three attempts |

---

## Benchmark Scenarios

### Scenario 1: FIRST_VISION (standard, 1-attempt success)
- **Expected**: total_ms ≈ 40,000–80,000
- **Expected breakdown**: fetch ~1s, vision ~5s, openai ~35–70s, upload ~2s
- **Cost**: ~$0.194 (MEDIUM risk)

### Scenario 2: FIRST_VISION (benchmark apartment, 1-attempt success)
- Same profile as Scenario 1 but larger source image (bay windows, complex room).
- **Expected**: similar timing; mask_generation may be slightly slower for complex perimeter.

### Scenario 3: STYLE_REFINEMENT (atmosphere switch, 1-attempt success)
- Prompt is shorter (SR path, smaller budget), mask is applied.
- **Expected**: prompt_ms slightly lower; openai similar.

### Scenario 4: FIRST_VISION with 1 retry (2-attempt scenario)
- Attempt 1 fails at ~60s timeout.
- **Expected**: total_ms ≈ 120,000–180,000
- **Expected breakdown**: openai_ms ≈ 120,000+ (x2 attempts)
- **Cost**: ~$0.384 (HIGH risk)

---

## What Was Instrumented (Wave 4.4.2)

| Component | Change | File |
|-----------|--------|------|
| PipelineTimer | New class for stage recording + summary | performance_observer.py |
| estimate_payload_bytes | Multipart payload size estimate | performance_observer.py |
| estimate_cost_usd | USD cost estimate by quality/size | performance_observer.py |
| cost_risk_label | LOW/MEDIUM/HIGH/CRITICAL tier | performance_observer.py |
| [PERF] image_fetch | Stage timing added | main.py |
| [PERF] vision_analysis | Stage timing added (finally block) | main.py |
| [PERF] prompt_composition | Stage timing added | main.py |
| [PERF] mask_generation | Stage timing added | main.py |
| [PERF] payload_estimate | Payload size log added | main.py |
| [PERF] openai_api | Per-attempt timing recorded | main.py |
| [PERF] supabase_upload | Stage timing added | main.py |
| [PERF SUMMARY] | End-of-request summary log | main.py |

---

## What Was NOT Optimized (Wave 4.4.2)

The following optimizations were evaluated and explicitly DEFERRED:

| Optimization | Risk | Decision | Rationale |
|-------------|------|----------|-----------|
| Switch quality=high → quality=medium | HIGH — visual regression | DEFERRED | quality=high is FROZEN; must benchmark before any change |
| Reduce input_fidelity=high → low | HIGH — fidelity regression | DEFERRED | input_fidelity=high is FROZEN |
| Reduce output size (always 1024×1024) | MEDIUM — proportion distortion | DEFERRED | Aspect-ratio matching is load-bearing for room proportions |
| Cache mask for same image across sessions | LOW-MEDIUM | DEFERRED | Needs cache invalidation strategy; safe to instrument first |
| Skip vision analysis for SR path | LOW-MEDIUM | DEFERRED | Vision grounding aids geometry preservation even in SR |
| Parallelize vision + mask | LOW | DEFERRED | Possible, but mask depends on image_bytes already in memory; safe only if image_bytes available before vision call |
| Reduce vision max_tokens (220→120) | UNKNOWN | DEFERRED | Could cut vision latency; unknown impact on room description quality |
| Async Supabase upload (fire-and-forget) | LOW | DEFERRED | Would hide upload errors from user; needs retry wrapper |
| OpenAI timeout tuning | MEDIUM | DEFERRED | Needs PROD data on actual P95 latency before setting timeout |

**Rule:** If an optimization has uncertain visual impact, DO NOT APPLY. Instrument, measure, defer.

---

## Remaining Risks (Post Wave 4.4.2)

1. **OpenAI timeout**: No explicit timeout set on images.edit call. The SDK default (600s) is used. First-attempt failures at ~60s are likely server-side timeouts or RemoteProtocolError from the existing httpx connection. **Needs PROD [PERF SUMMARY] data to determine optimal timeout.**

2. **Retry cost amplification**: With max_attempts=3 in PROD, worst-case cost is ~$0.574 ($0.570 images + $0.004 vision). The CRITICAL cost_risk label will fire for 3-attempt sessions.

3. **Vision analysis latency**: ~3–8s added unconditionally to every request. Non-fatal but always present. **Candidate for parallelization once image_fetch timing is measured.**

4. **No deduplication of vision calls**: If a client retries the same request (same client_request_id), the full pipeline re-runs. The client_request_id is logged but not used for deduplication.

---

## Manual PROD Checklist (Wave 4.4.2)

1. Restart backend. Confirm `[PERF SUMMARY]` appears in logs for each /generate call.
2. Run a standard FIRST_VISION request. Record `total_ms`, `openai_ms`, `est_cost_usd`.
3. Confirm `cost_risk=MEDIUM` for single-attempt success.
4. If a retry occurs, confirm `cost_risk=HIGH` and `openai_ms (x2 attempts)`.
5. Confirm no regression in [GenerationProfile] logs (quality=high, input_fidelity=high).
6. Confirm `compression_applied=False` or `removed_sections=[]` for standard rooms.
