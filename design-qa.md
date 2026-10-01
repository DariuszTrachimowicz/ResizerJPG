# Design QA - Resizer JPG 2.1.0

## Target And Evidence
- Source visual truth: user-selected `exec-668e30ee-27f1-42d8-8e67-ad0156df53d2.png` in the Codex generated-images directory for this task.
- Implementation: native Windows PowerShell 5.1 WPF, not a web prototype.
- Rendered content viewport: 1440 x 1024 logical pixels, 96 DPI. Source raster: 1487 x 1058, resized to 1440 x 1024 for comparison. Native OS title chrome is excluded from WPF content renders; mock title buttons are not recreated as application controls.
- Full comparison: `work/design-comparison.png` (2880 x 1048 including comparison labels).
- Focused comparisons: `work/design-inspector-comparison.png` and `work/design-footer-comparison.png`.
- Implementation renders: `work/design-implementation.png`, `work/design-compact.png` (984 x 641 client area of 1000 x 680 outer window).
- State: Makalu Sklep, Auto, Pad, quality 85, 72 DPI, Original, fitted zoom; 24 included photos in two groups, MAK_1042.jpg selected.
- Fixture differences: synthetic product photo repeated across 24 test inputs, not real Makalu merchandise. Source dimensions 1024 x 1536 are correctly reported in Original mode. Names, group counts, photos and scroll position differ from the mock. Test images are excluded from the portable release.

## Comparison History
1. Initial functional render and compact regression exposed P1 fitted-image cropping: image plus margin 545 px versus a 217 px viewport. Inspector quality was below the initial compact view. Also found P2 duplicate filename, raw English orientation and truncated zoom caption. Result: blocked.
2. Replaced old ScrollViewer viewport sizing with the current parent surface; reduced compact inspector spacing; collapsed advanced fields by default; replaced duplicate heading with orientation, displayed per-photo export status, and shortened the zoom caption. Native routed-event tests confirmed fit, cancellation, validation focus and modal focus.
3. First combined full-view comparison showed excessive inspector compression at desktop height and narrower queue proportions than the reference. Result: blocked. Restored spacious desktop margins while retaining compact margins; adjusted desktop queue/inspector tracks; ordered ingestion by ascending filename. Regenerated the same state and repeated the combined full-view and focused comparisons.
4. Final capture: fitted image 365 x 548 inside 664 x 588 desktop viewport; compact 110 x 165 inside 382 x 205. Quality, destination, filename, inclusion count and export remain visible. No remaining actionable P0/P1/P2 visual findings in the inspected states.

## Fidelity Surfaces
- Typography: Segoe UI native desktop family, stable 14 px control text, 26 px product title and 18 px panel heading. Metadata is deliberately smaller; filename and paths have readonly keyboard-accessible fields. No overlaps observed.
- Layout rhythm: three unframed working columns, centered full-photo preview, filmstrip and persistent footer. Desktop inspector has more space; compact inspector keeps primary settings visible and scrolls only expanded advanced content.
- Colors: neutral white/gray surfaces, cyan accent and light blue selection. No dominant gradients or decorative illustration substitutes.
- Image quality/assets: original owner logo and multi-resolution program icon preserved; Lucide controls retained. Actual JPEG data renders in queue, filmstrip and preview without blank surfaces or distorted proportions. Generated fixture is only for visual testing.
- Copy/content: Polish task labels, Makalu default, explicit selected-photo export count, concrete `_R` filename and actual output path, creator and 2.1.0 footer. Native update/log actions remain available.

## Intentional Differences And Limits
- Advanced fields are collapsed initially to preserve the compact workflow. The mock's undo/redo symbols are not added: this app has no destructive photo-edit history.
- Extra select-all, clear, log, stop and open-output actions support the real workflow. Folder choosing uses an icon command rather than a fictitious dropdown.
- Fit-relative zoom is not pixel 1:1. Original preview is capped at 2048 px; Result uses the actual final JPEG dimensions and encoding settings.
- Regression tests operate WPF routed events and RenderTargetBitmap. They do not prove physical Explorer drag/drop, high-DPI multi-monitor behavior, performance on a large real-product library or full screen-reader compliance. Live-region event hooks were reviewed, not tested with a screen reader.
- No browser console exists for this native app. PowerShell parser, worker errors and export logs are checked instead.

## Checklist
- [x] Approved and implemented visuals opened and compared together.
- [x] Full-view and focused inspector/footer comparisons reviewed.
- [x] Desktop and compact renders inspected after fixes.
- [x] Selection independent of inclusion, preview/filmstrip navigation and real JPEG export tested.
- [x] Keyboard-focus controls, full paths, validation focus, cancellation and modal focus covered.

## 2.2.0 Close-Icon Follow-Up
- User screenshot exposed a gap in the original desktop-state QA: modal close icons had not been checked pixel-by-pixel.
- Reproduced actual modal appearance: `work/icon-before-updates.png`. The second independent SVG path was shifted beyond the 24-unit icon canvas.
- Source conversion now resets the origin before subsequent relative initial moveto commands, preserving their relative line semantics. Only X, download and image data changed.
- Revised native modal captures: `work/icon-after-updates.png`, `work/icon-after-log.png`. Both display the complete intersecting X. Modal size/density unchanged; crops are actual WPF panels at 96 DPI.
- `Test-Icons.ps1` confirms five pixel references, stroked bounds and X endpoints/intersection. Its `-CheckDialogs` mode checks both actual close bindings, click/Escape, modal dismissal and focus restoration. Baseline failed, revised build passed.
- Independent Gemini review: PRZYJETE, round 1, no findings. This does not substitute for actual screen-reader or physical-input testing.

## 2.2.0 Help And GPL Follow-Up
- Question-circle help command added to the header; GPLv3/no-warranty document link and copyright stay in the existing 28px footer. Help instructions remain in the external offline README, not in the working layout.
- Native compact/desktop renders: `work/icon-fix/work/help-review-layout/help-1000x680.png` and `work/icon-fix/work/help-review-layout/help-1440x1024.png`. Inspected both with the longer update caption; help, title, credits, GPL and version do not overlap or clip.
- `Test-HelpLicense.ps1` passed exact local-document routing, keyboard focus, accessible names, missing-file recovery, opener errors, trusted editor arguments, GPL hash and layout bounds. GPL text uses upstream bytes; `.gitattributes` prevents checkout conversion. Third-party license notices and brand PNG/ICO unchanged.
- Combined Gemini review: PRZYJETE, round 1, no findings. Core, queue (16 cases), models, icon/dialog, package/installer and original v2.0 updater tests passed in the isolated reviewed checkout. Full portable WPF test passed real JPEG export, cancellation, preview, routed drops and update comparison.
- A provisional local 2.1.1 package was used for X regression only; it was never published. All fixes are released together as 2.2.0.
- Final main portable package repeated Help/GPL, icons/dialogs, layout, installer/rollback, legacy 2.0 updater and full WPF export tests successfully. Real Help click started trusted Notepad with the exact local README argument; existing user editor processes were not closed. Editor launch receipt does not certify the visual contents of every Notepad tab.

final result: passed
