# Wave 5.5.17b — Competitor Architecture Audit

**Date :** 2026-05-24
**Type :** read-only research audit (no code)
**Trigger :** Wave 5.5.15/16 family confirmed that pure prompt engineering on gpt-image-1 hits a ceiling for furniture realism. Question : how do market-leading AI interior design apps add TVs / tables / lamps reliably without architectural drift ?
**Methodology :** Web research (Pieter Levels tweets, open-source repos, HF model cards, product pages, pricing). Conducted via background research agent.

---

## 1. Per-app summary

| App | Likely tech stack | Evidence (strength) | Strengths | Limitations |
|---|---|---|---|---|
| **RoomGPT (roomgpt.io)** | Stable Diffusion + ControlNet, hosted on Replicate; Next.js front end; Bytescale storage; UpStash for rate limiting | **HIGH** — full open-source repo on GitHub ([Nutlope/roomGPT](https://github.com/Nutlope/roomGPT)), README explicitly names ControlNet + Replicate | Cheap, fast, preserves room geometry well | Style transfer, not true "add new furniture"; output often reshuffles existing furniture rather than densifying it |
| **Interior AI (interiorai.com)** | **Stable Diffusion 1.5 (still !) + SDXL**, image-to-image with depth + semantic segmentation, custom forks; runs on owner's own GPU infra | **HIGH** — Pieter Levels public tweets (Sept 2025 : "SD 1.5 and SDXL is king at redesigning interiors, no model ever came close, not even Flux"). Says new version has "3D depth perception" + "3D construction segmentation" for walls/floor/ceiling | Mature, fast iteration, supports restyle + virtual staging | Old base model; some output dated; struggles with extreme angles |
| **Reroom.ai (Stylefie, Inc.)** | Almost certainly Stable Diffusion + ControlNet variant; product copy mentions "vast collection of furniture and decor items from various brands" — suggests either (a) RAG into diffusion or (b) post-hoc product matching | **LOW** — no public technical disclosure | Style breadth (20+ styles), prompt control, brand-matched furniture | No public architecture, no proof furniture is generated vs. matched from catalog |
| **AI Room Planner (airoomplanner.com)** | Generic SD + ControlNet stack, no proprietary signal | **LOW** — no technical disclosure; free tier suggests commodity inference | Free, easy | Generic outputs, no differentiation |
| **Foyr Neo (foyr.com)** | **NOT primarily generative.** CAD + 3D rendering platform with 60,000-item parametric furniture library; AI is layout suggestion + product matching. Renders produced by 3D engine, not diffusion | **HIGH** — own marketing + demo videos show drag-and-drop 3D + ray-traced renders | Pixel-perfect furniture (real 3D geometry), photorealistic 4K renders | Heavy workflow; requires modeling the room first; not "upload photo → restyle" |
| **Decorilla (decorilla.com)** | **Hybrid : AI for designer-matching + product recommendation, human designers do actual styling, 3D rendering tools render the result.** AI "Catherine" is workflow AI, not image generator | **HIGH** — own pages describe service as AI-assisted human design | Quality high (humans in loop) | Not comparable to our product (service, not app) |
| **Homedesigns.ai / Decoratly / Spacely / DecorAI** | Same commodity pattern : SD + ControlNet on Replicate / Fal / RunPod | LOW — no public info, but pricing ($10–30/mo) consistent with commodity ControlNet inference (~$0.01/image on Replicate) | Cheap, fast | Same furniture-deficit problem as the rest of the category |

---

## 2. Architectural pattern recognition

**3 dominant patterns** in the category :

### Pattern A — Single-pass ControlNet on Stable Diffusion *(~80% of category)*
- One forward pass : user photo → ControlNet conditioner (depth, canny, MLSD lines, or semantic segmentation) → SD/SDXL generates the styled image, structurally locked to the conditioner.
- **This is the same ceiling we hit with gpt-image-1**, just from a different direction. It restyles existing pixels well; does NOT reliably add net-new furniture because the conditioner pins existing geometry.
- Canonical reference : ML6's open-source [BertChristiaens/controlnet-seg-room](https://huggingface.co/BertChristiaens/controlnet-seg-room) and [ml6team/fondant](https://github.com/ml6team/fondant-usecase-controlnet) pipeline (LAION5B, 130k interior images, 15 room types, BLIP captions, UperNet segmentation).
- **Apps using this : RoomGPT, Interior AI, Reroom, AI Room Planner.**

### Pattern B — Multi-stage segmentation + targeted inpainting *(emerging best practice)*
- Step 1 : depth + semantic segmentation (UperNet or SAM) extracts walls/floor/ceiling/windows as structural lock mask
- Step 2 : Grounding DINO + SAM identifies "stageable floor area"
- Step 3 : ControlNet-inpainting fills ONLY the floor region with furniture, structural mask preventing wall/window touchups
- **This is what virtual staging companies built specifically to add furniture to empty rooms — exactly our problem, inverted.**
- Most credible technical answer to the furniture-deficit problem.
- Reference : [mithunparab/virtual-staging](https://github.com/mithunparab/virtual-staging) repo, [SegMind AI Virtual Furniture Staging](https://www.segmind.com/pixelflows/ai-virtual-furniture-staging/api) commercial.

### Pattern C — CAD library + 3D rendering, AI for recommendation only
- Furniture = real 3D geometry from curated catalog. AI suggests layouts; renderer produces pixels
- **Only architecture that GUARANTEES correct furniture** (literally inserted, not generated)
- Fundamentally different product (modeling tool, not photo-restyle app)
- **Apps : Foyr Neo, Decorilla.**

---

## 3. Cost / effort matrix for adopting each path

| Path | Data needed | Training compute | Engineering time | Ongoing inference cost | Likelihood of solving furniture deficit |
|---|---|---|---|---|---|
| **A. Fine-tune gpt-image-1** | N/A — OpenAI does not currently allow fine-tuning gpt-image-1 (as of 2025/early 2026 per OpenAI docs); only some text models support fine-tuning | N/A | N/A | N/A | **BLOCKED.** Not an option today. Revisit when/if OpenAI opens it |
| **B. Train LoRA on SDXL + ControlNet inpainting** | ~50–500 curated furnished-room images per style; benchmarks already exist | ~$50–200 per LoRA on rented A100 (few hours); LoRA = ~98% fewer parameters than full fine-tune | 2–4 weeks for small team to stand up SDXL + ControlNet-seg + ControlNet-inpaint pipeline + LoRA training loop. Needs GPU ops (Replicate / fal.ai / self-hosted) | Replicate's `rocketdigitalai/interior-design-sdxl-lightning` benchmark : **~$0.011/image, ~9 sec/image**. ~10–50x cheaper than gpt-image-1 | **HIGH for furniture density.** But re-inherits SD/SDXL aesthetic ceiling (less crisp than gpt-image-1 on materials, fabric, lighting). Real quality trade-off |
| **C. Hybrid pipeline : segmentation → inpainting → composition** *(keep gpt-image-1 OR move to SD)* | No training data required up front — off-the-shelf SAM + Grounding DINO + pretrained ControlNet-inpaint | None for v1 | 3–6 weeks. Lift is real : SAM/DINO inference, mask generation, two-stage diffusion calls, compositing. Every component well-documented + open source | If gpt-image-1 for first pass + only inpaint floor region on second pass : ~2x current. If full SD + ControlNet : ~10–50x cheaper | **HIGHEST** for specific "add furniture without architectural drift" problem — this is literally what virtual staging companies built |
| **D. Stay with pure prompt engineering** | None | None | None | Current cost | **LOW.** Our own benches already show the ceiling. Category-wide ceiling (all single-pass diffusion apps have empty-room-feel) |

---

## 4. Recommendation

For our personal / early-stage product, ranked :

### 1. Best ROI : Path C (hybrid segmentation + targeted inpainting), staying on gpt-image-1 for first pass

- Preserves architectural-preservation quality already won (Wave 5.5.4+5.5.6)
- Adds focused second pass that ONLY paints in floor region (where furniture should go) using segmentation mask to forbid wall/window edits
- Avoids retraining, avoids moving off gpt-image-1, directly addresses furniture deficit
- Implementation lift : 3–6 weeks for single dev with GPU access
- **Risk** : gpt-image-1's "partial edits often result in global changes" limitation (well-documented). May need fallback to SDXL inpainting for floor-region step

### 2. Second-best : Path B (SD/SDXL + ControlNet), only if accepting aesthetic downgrade

- Cheaper inference, more control, BUT SD aesthetic visibly weaker than gpt-image-1 on textiles, lighting, "feel"
- That "feel" is what our atmosphere DNA exists to deliver. Probably wrong for this product

### 3. Wait for better foundation model : legitimate but not free

- gpt-image-1.5 / hypothetical gpt-image-2 will likely close some gap, AND OpenAI may eventually open fine-tuning
- But competitors are not waiting; 6–18 month wait carries product-momentum cost

### 4. Path A (fine-tune gpt-image-1) is BLOCKED. Don't plan around it.

### 5. Path D (status quo) is the documented ceiling. Confirming what our benches already told us.

---

## 5. Open questions (what we couldn't infer)

- **Reroom's "furniture catalog from various brands"** — RAG-into-diffusion (catalog images as reference into diffusion model) or post-hoc product matching for affiliate revenue ? Matters because RAG-into-diffusion would be a 4th architectural pattern worth studying
- **Whether Interior AI's "3D construction segmentation"** is a separate inference step or just ControlNet-seg under marketing name
- **gpt-image-1's actual masked-region inpainting fidelity** for furniture — `images.edit` accepts mask, but third-party reviews note "partial edits often result in global changes". Needs direct bench BEFORE committing to Path C with gpt-image-1
- **Whether any competitor uses depth-conditioned generation specifically to plant furniture geometrically** vs. just for room shape preservation
- **Reroom's actual conversion-quality numbers** for "add furniture" prompts vs. "restyle" prompts. Without seeing their bench, we don't know if they actually solved this or just have prettier marketing photos

---

## 6. Sources

- [Nutlope/roomGPT on GitHub](https://github.com/Nutlope/roomGPT) + [README](https://github.com/Nutlope/roomGPT/blob/main/README.md) — primary evidence for RoomGPT's ControlNet + Replicate stack
- [BertChristiaens/controlnet-seg-room on Hugging Face](https://huggingface.co/BertChristiaens/controlnet-seg-room) — canonical open-source interior ControlNet reference (130k LAION5B images, 15 room types, BLIP + UperNet)
- [ml6team/fondant-usecase-controlnet on GitHub](https://github.com/ml6team/fondant-usecase-controlnet) + [ControlNet docs](https://github.com/ml6team/fondant-usecase-controlnet/blob/main/docs/controlnet.md) — end-to-end data pipeline
- [ControlNet for Interior Design (ml6team HF Space)](https://huggingface.co/spaces/ml6team/controlnet-interior-design)
- [Pieter Levels tweet on SD 1.5 / SDXL for Interior AI](https://x.com/levelsio/status/1966610839068463477) + [original launch tweet](https://x.com/levelsio/status/1757388544543220097)
- [mithunparab/virtual-staging on GitHub](https://github.com/mithunparab/virtual-staging) — SAM + Grounding DINO + ControlNet-inpaint pipeline
- [SegMind AI Virtual Furniture Staging](https://www.segmind.com/pixelflows/ai-virtual-furniture-staging/api)
- [Reroom AI support / about](https://reroom.ai/support/about) — product copy only
- [Foyr Neo](https://foyr.com/) + [60K-product library description](https://aitools.aiting.com/ai/foyr-neo)
- [Decorilla AI tools overview](https://www.decorilla.com/online-decorating/ai-interior-design-for-room-design/)
- [Replicate pricing](https://replicate.com/pricing) + [rocketdigitalai/interior-design-sdxl-lightning](https://replicate.com/rocketdigitalai/interior-design-sdxl-lightning)
- [OpenAI gpt-image-1 docs](https://developers.openai.com/api/docs/models/gpt-image-1) + [Rendair gpt-image-1 review](https://rendair.ai/blog/models-gpt-image-1-for-interior-designer-practical-overview) — confirms no fine-tuning available, documents partial-edit limitation
- [MindStudio : What is SDXL LoRA](https://www.mindstudio.ai/blog/what-is-sdxl-lora-custom-styles)
- [Bartosz Ludwiczuk : Generative Interior Design Challenge 2024, 2nd place](https://medium.com/@melgor89/generative-interior-design-challenge-2024-2nd-place-solution-6338f19f6fe3)
