# Validation log — H7 band vs Apple Watch

Reference device: his Apple Watch (worn on the other wrist).
All times PT.

## 2026-10-16 — first day

### 14:25 — baseline at pairing
- Apple Watch: 7,101 steps (full day total)
- Band: freshly paired, count starts ~0

### 14:29 — 100-step walk test
- Real counted steps: 100
- Band: 101 (+1% error — essentially perfect)
- Apple Watch: 7,101 → 7,185 = 84 counted (−16% undercount)
- Verdict: band beat the Watch on this test. Single walk, small sample.

### 14:53 — extended step comparison
- Band total: 459 steps
- Apple Watch: 7,559 (expected 7,101 + 459 = 7,560 — off by ONE step)
- Verdict: essentially identical. His sharp catch: the earlier 100-step "undercount"
  was Watch update latency, not real undercounting — the Watch batches step
  delivery to the phone, the band reports live.

### Tonight → morning sleep comparison (capture these)
Wear both to bed. In the morning, open the vendor app FIRST (let it sync the
night), then Apple Health → Sleep. Record:
- [ ] Your actual lights-out time and actual wake time (best estimate)
- [ ] Band: sleep window start / end, total duration
- [ ] Band: stage breakdown if shown (light / deep / REM) — treat as estimates
- [ ] Watch (Health): sleep window start / end, total duration
- [ ] Watch: stage breakdown (Health shows awake/REM/core/deep on recent models)
- [ ] Deltas: window-start diff, window-end diff, duration diff
- [ ] Confounders: which wrist each device is on, any wake-ups you remember,
      whether the band stayed on all night
- Screenshots: vendor app sleep screen + Apple Health sleep graph (one each)

### Morning step totals (pending)
- [ ] Compare step totals after the night (give the Watch a few minutes — it batches step delivery)

### Still needed
- [x] Firmware version + model name from their app's device info screen → H7, firmware 00.72.00.07-5927 (2026-10-16 14:50 PT)
