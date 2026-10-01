# Photo Queue Implementation Plan

> **For agentic workers:** Use the approved image and disjoint worker scopes. Preserve the existing PowerShell 5.1 desktop runtime. No web scaffold.

**Goal:** Implement the selected thumbnail-queue design in the real Windows Resizer.

**Architecture:** Keep the System.Drawing resize engine and hidden VBS launcher. Add a plain-data queue/export module, WPF notification models and runspace jobs for scanning, preview and exporting. The dispatcher only applies results to controls; workers never access controls.

**Tech Stack:** Windows PowerShell 5.1, WPF, System.Drawing, existing Lucide assets.

**Spec:** The user-selected image `exec-668e30ee-27f1-42d8-8e67-ad0156df53d2.png` from the preceding design exploration.

## Global Constraints
- Default Makalu Sklep: portrait 1920 x 2880, landscape 2880 x 1920, JPEG quality 85, 72 DPI in both axes.
- Auto uses EXIF-normalized orientation. Pad preserves the complete photo on white; Crop remains available.
- Original files stay unchanged. Output defaults to `resize` with `_R`; collisions are numbered.
- Single JPG/JPEG, multiple folders, drag/drop and recursive paths remain supported.
- Preserve Digital Xperts logo, d-x.pl, Dariusz Trachimowicz, version footer and GitHub updates.
- Photo selection for preview is independent of inclusion in the exported batch.
- No manual crop editing, rotation, cloud upload or invented output-size statistics.

## Task 1: Queue And Export
Files: `ResizerQueue.ps1`, `tests/Test-Queue.ps1` (queue worker).
- [x] Write and run failing fixtures for overlapping roots, EXIF, exclusions, selected subsets, corrupted JPG and cancellation.
- [x] Implement `Get-ResizerQueueItems`, `Get-ResizerQueueTargetPath`, `Invoke-ResizerQueueExport`, `Get-ResizerPreviewData`.
- [x] Verify fixture outputs, dimensions, DPI, names, hashes and callback counts.

```powershell
powershell -NoProfile -File tests/Test-Queue.ps1
```

## Task 2: Layout And Notification Models
Files: `ResizerWindow.xaml`, `tests/Test-WindowLayout.ps1` (designer); `ResizerUIModels.ps1`, `tests/Test-UIModels.ps1` (main).
- [x] Run failing layout/model contract tests.
- [x] Build grouped, collapsible thumbnail queue, central preview/filmstrip, compact inspector and fixed export footer.
- [x] Implement notifications for inclusion, thumbnail, details, output and status.
- [x] Verify XAML loading and model notifications.

```powershell
powershell -Sta -NoProfile -File tests/Test-WindowLayout.ps1
powershell -Sta -NoProfile -File tests/Test-UIModels.ps1
```

## Task 3: Dispatcher And Jobs
Files: `ResizerUI.ps1` (main), `tests/Test-WpfUI.ps1` (QA worker).
- [x] Run failing queue tests against the old UI.
- [x] Wire scan, preview and frozen export jobs with cancellation and bounded dispatcher message consumption.
- [x] Add independent inclusion/counts, synchronized queue/filmstrip selection, Pad/Crop and fitted-preview zoom.
- [x] Preserve update jobs, hidden installer and safe closing. Ignore stale preview generations.
- [x] Validate add/drop, subset export, cancel/restart, parameter validation and compact layout.

```powershell
powershell -Sta -NoProfile -File tests/Test-WpfUI.ps1
```

## Task 4: Visual And Regression Receipt
- [x] Render the selected state at the reference viewport and compare to the approved image.
- [x] Correct clipped labels, empty imagery, wrong hierarchy and focus states.
- [x] Independently review accessibility risks and workflow regressions.
- [x] Test existing engine, launcher, packages and installer.
- [x] Bump version to 2.1.0, update docs and build all portable output.

```powershell
powershell -NoProfile -File tests/Test-Resizer.ps1
powershell -Sta -NoProfile -File tests/Test-Launcher.ps1
powershell -NoProfile -File Build-Portable.ps1
powershell -NoProfile -File tests/Test-Updates.ps1
```

## Receipt Limits
Static WPF render and routed-event tests do not establish physical Explorer drag/drop, real-product performance or full assistive-technology compliance. Record these separately from verified behavior. Publish a new GitHub release only after local and CI checks pass; do not alter v2.0.0.
