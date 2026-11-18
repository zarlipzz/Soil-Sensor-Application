# Remaining Soil App Features Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement remaining checklist items: relocate START button to bottom in portrait/landscape, add 10-second countdown on START button, decouple map pins to 1-to-1 without grouping, add checkbox filtering for local history log search, add raw log export button with selection to AppBar, and position unit strings at bottom-right of sensor cards.

**Architecture:** 
- `DashboardScreen`: Re-order layout in portrait (Map -> GPS/Name -> 8 Cards -> START button at bottom) and landscape (Left: Map, Right: GPS/Name -> 8 Cards -> START button at bottom). Add 10-second countdown state during measurement sampling. Add export button to AppBar. Change map markers from group-based to 1-to-1 (`measurementMarkerPoints`).
- `SensorCard`: Separate numerical value and unit. Position unit string at bottom-right (`Positioned(right: 0, bottom: 0)`), scale value text to avoid overlapping, and pass unit tests.
- `LocalHistorySheet` & `ExportHistorySheet`: Provide checkbox selection for filtering logs by "ทั้งหมด" (All), unique Names, and unique Dates. Provide raw CSV/JSON export triggered directly from AppBar with matching selection dialog.

**Tech Stack:** Flutter 3, Dart, `flutter_map`, `latlong2`, `shared_preferences`, `share_plus`, `path_provider`.

---

### Global Constraints
- Target device: Samsung Galaxy Tab A9 (both Portrait and Landscape).
- No overflow errors (`A RenderFlex overflowed...`).
- Measurement name must remain required before START.
- Unit of each parameter must be at bottom-right of white card.
- 1 measurement with GPS = 1 green pin on map with name label.

---

## Tasks

### Task 1: Fix syntax error in `dashboard_screen.dart` and verify existing tests
- Modify `lib/screens/dashboard_screen.dart:748-796` to fix the bracket/parenthesis syntax error.
- Run `flutter test` to verify tests compile and establish baseline.

### Task 2: SensorCard unit separation and layout
- Modify `lib/widgets/sensor_card.dart` so `value` displays numeric value and `unit` is rendered at bottom-right in `Positioned(right: 0, bottom: 0)` inside padding.
- Update `lib/screens/dashboard_screen.dart` to pass clean values and units to `SensorCard`.
- Verify `test/sensor_card_test.dart` passes.

### Task 3: Map 1-to-1 Pin Presentation (Requirement 6 & 7)
- In `lib/screens/dashboard_screen.dart`, replace `measurementMarkerGroups` with direct 1-to-1 markers using `gpsEnabledMeasurements(_localLogs)` and `measurementMarkerPoints`.
- Render a green pin marker with measurement name label for each measurement.
- Tapping the marker opens that measurement's details dialog.
- Update/add test in `test/measurement_name_map_test.dart`.

### Task 4: START Button UI, Relocation, and 10s Countdown (Requirements 1 & 5)
- In `lib/screens/dashboard_screen.dart`:
  - Change button label to `START` when idle/ready.
  - Implement 10-second countdown (`_countdownSeconds = 10` decreasing every second down to 1s) while measuring.
  - Pace sampling over the 10 seconds (~1 sample per second) to gather 10 valid samples, average them, and display the single average.
  - Move START button to the bottom in Portrait (under the 8 cards, matching Image 2).
  - Move START button to the bottom in Landscape (under the 8 cards on right pane, matching Image 1).
  - Adjust card aspect ratios and layout so all 8 cards fit the remaining space cleanly without overflow.

### Task 5: Checkbox Log Search/Filter & AppBar Export Raw File (Requirements 8 & 9)
- In `lib/widgets/local_history_sheet.dart`:
  - Add filter modal/section with checkboxes: "ทั้งหมด", unique names list, and unique dates list.
  - Filter records based on selected checkboxes.
- In `lib/screens/dashboard_screen.dart`:
  - Add raw file export icon button on AppBar next to history icon.
  - Tapping export icon opens an export dialog/sheet with the same checkbox selection (All, by Name, by Date, or specific records) and format choices (CSV / JSON raw file).
- Write widget/unit test verifying checkbox filter logic and export dialog.

### Task 6: End-to-End Verification and Documentation
- Run `flutter analyze` and `flutter test`.
- Update `lib/agent.md` with new layout, START countdown, 1-to-1 pins, checkbox filters, and AppBar export.
