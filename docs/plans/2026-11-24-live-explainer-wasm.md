# Plan: the explainer's live demo on the app's own code (story 014)

Lands after PR #11 merges. No code yet: this plan is for Igor's "do it".

## Shape

1. **`AudioCore` becomes portable, Foundation-free.** Today `Levels`, `FFT`, `Pitch` and `Processing` call vDSP
   (Accelerate), and `NoiseMetrics`, `MicController` and `JSONNumber` import Foundation. Split:
   - a new target `AudioMath` (plain Swift stdlib only: no Foundation, no Accelerate) holding RMS, peak, decibels,
     `LevelSummary`, `Separation`, `frameLevelsDB`, the spectrum's bins and the spectrogram's pixel mapping, plus a
     plain radix-2 FFT;
   - `AudioCore` keeps the vDSP fast paths and re-exports `AudioMath`; the app is unchanged. The scalar FFT is used
     only where vDSP is absent (`#if canImport(Accelerate)`).
   - maths functions need `log10`/`pow`: from `Darwin` / `Glibc` / `WASILibc` behind `canImport`, never Foundation
     (the context-grabber pt1e lesson: Foundation drags ICU in, 55.9 → 14.9 MB there).
2. **`AudioWasm` target**: a WASI reactor exporting a C ABI (`@_expose(wasm)` + `@_cdecl`, as BoardWasm):
   `ad_alloc(n)` for a Float32 buffer in linear memory, `ad_frame(ptr, n, rate)` → RMS/peak dB, `ad_spectrum(ptr, n,
   out)`, `ad_summary(levelsPtr, n, out)` → floor, median, speech, separation, band index. No strings across the
   boundary, so no JSON and no Foundation.
3. **The page**: `docs/noise.html` gains a "Live demo" panel with a "Load live demo" button. On press it adds a
   `<script src="noise-demo.js">` that carries the wasm inline as base64 (a `fetch` of a `.wasm` fails on `file://`
   in Chrome and Safari, and H opens the bundled page from a file). Scenes are synthesised in JS (noise colours,
   hum, a formant-shaped "voice" burst pattern) at 16 kHz; "Use my mic" uses `getUserMedia` + an AudioWorklet
   posting 1024-sample blocks. Drawing is canvas at 30 Hz; the maths is all wasm.
4. **Build**: `just wasm` (swift.org toolchain + its wasm SDK; this Mac has none: Apple's toolchain cannot target
   wasm, so the build runs on the Linux box or after `swift sdk install`). Writes `docs/noise-demo.js`, committed so
   Pages and `just app` need no toolchain; `just app` bundles it beside `noise.html`.

## Trade-offs

| Choice | Size (est.) | Effort | Risk |
|---|---|---|---|
| **Embedded Swift → wasm (recommended)** | ~50–200 KB | low for pure maths | needs the subset: no `Any`, existentials or Foundation; numeric code fits |
| Full WASI SDK, no Foundation | ~1–3 MB | low | bigger download, still fine behind a button |
| WASI SDK with FoundationEssentials (BoardWasm's way) | ~15 MB | low | too heavy for a page demo |
| Port the maths to JS | ~10 KB | medium | two copies of the maths drift apart: the thing Igor wants avoided |

## Tests

- Host: parity tests, the scalar path against vDSP within 1e-4 dB on noise, tones and the 50 ms frame summary;
  `AudioMath` builds on Linux with no Foundation (`swift build` on Linux catches an import).
- Wasm: a Node script loads the module, feeds the same synthetic clips and compares with expected values the host
  tests write (the "same answer as the app" scenario).
- Browser: headless Chrome and a WKWebView probe (as in today's #11 check) at 1100 and 390 px: no console errors, no
  sideways scroll, button loads, scenes run. iPhone Safari and the mic prompt are a person's check.

## Risks and open questions

- `getUserMedia` on `file://`: Chrome allows it with a prompt; Safari likely refuses. The mic scenario then says so
  and points to the Pages copy (#9), which is https.
- Embedded Swift on wasm is still marked experimental in the toolchain; if it fights us, fall back to the full SDK
  without Foundation (row 2).
- iOS's H opens the web URL until #8/#9; the demo there waits for Pages.

## Steps (one PR)

1. Story 014 and this plan (this commit).
2. `AudioMath` split + parity tests; app unchanged (`just test`, `just selftest`, `just ios-build`).
3. `AudioWasm` + `just wasm` + Node parity check.
4. The panel in `noise.html`, `noise-demo.js`, bundling in `just app`; browser checks; story 014 Status.
