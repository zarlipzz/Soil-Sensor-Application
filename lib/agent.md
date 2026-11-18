# Soil App: working context

## Purpose

Flutter Android application for a CH340 USB Modbus RTU **8-in-1 soil sensor**.
It reads a sensor packet, attaches the device GPS position, displays the live
values, stores a local history, and updates Home Assistant sensor entities.

Workspace root: `D:\Application_intern001\soil_app`  
This file is in `lib`, so paths below are relative to `lib/` unless noted.

## Current behavior

1. Android detects a CH340 USB sensor, obtains USB permission through the
   bundled `usb_serial` plugin, opens the port at 9600 8N1, then initializes it.
2. Initialization lasts approximately three seconds. The app sends the existing
   Modbus request during this period, validates replies, and discards every
   response. It becomes **READY** only after receiving at least one valid CRC
   frame.
3. User taps the single **Read sensor** / START action once.
4. `MeasurementEngine` collects exactly 10 valid complete Modbus samples. It
   rejects invalid/incomplete samples, retries failed/silent queries while its
   timeout remains active, and prevents concurrent starts and requests.
5. The app averages all eight parameters across those 10 samples, keeps all
   raw samples, attaches the current GPS data when available, then creates one
   `SoilMeasurement` record.
6. The one completed record is saved locally before `HomeAssistantService`
   updates Home Assistant sensor states. It is marked synced only if all
   required state updates succeed.

Before START, the user must enter a non-empty measurement name. The name is
trimmed, supports Thai/English, is locked while sampling, and is stored with
the completed record. There is intentionally no separate save button: one
completed START operation creates one local record and one Home Assistant
synchronization attempt.

## Implemented work

### USB lifecycle and initialization (Tasks 1–2)

- CH340 discovery uses VID `0x1A86` or a `CH340` product-name match.
- USB attach/detach events are observed once per service instance.
- Connection checks and permission/open operations are single-flight, avoiding
  duplicate Android permission prompts or duplicate port listeners.
- A permission denial is remembered only for the current Android USB device
  ID. Disconnect/reconnect or an explicit retry permits a new request because
  Android USB permission is not permanent across physical sessions.
- Disconnect cancels timers and stream subscriptions, closes the port, clears
  the Modbus buffer, resets READY, and stops an active measurement.
- Every successful new connection runs the 3-second initialization sequence.
- Transient sensor disconnection / reconnection snackbar notifications are disabled
  to eliminate frequent popups caused by loose cables. Instead, the START button
  color directly reflects connection state: grey when disconnected/unready, and
  green when connected and ready to press.
- CRC-invalid frames and silent Modbus queries can trigger a retry during an
  active measurement; they never create a measurement record.

### Measurement engine and storage (Tasks 3–4)

- `MeasurementEngine` owns one collection session: 10 valid samples, one
  timeout, no continuous measurement after completion.
- The button is labeled **START**. When tapped, a 10-second countdown runs
  on the button UI (`START (10 วินาที)` down to `1 วินาที`), and Modbus queries
  are paced over the 10-second window (~900ms per sample) to gather 10 valid samples.
- Timeout, disconnect, permission denial, initialization failure, or explicit
  cancellation stop the session without saving an incomplete record.
- A completed measurement stores average values and `raw_samples` together
  under the same `measurement_id`.
- `measurement_name` is stored on each measurement and the dashboard requires
  a non-empty name before START.
- SharedPreferences remains the local database with its existing maximum of
  200 records. Existing records remain readable and are not fabricated with
  missing raw samples.
- Local save de-duplicates by measurement ID, preventing retries from adding a
  second local record.
- A persistent app-installation UUID is generated once in SharedPreferences.
  It deliberately does not use IMEI or a restricted hardware identifier.
- Device metadata records platform, app version, Android manufacturer, model,
  and OS version using `device_info_plus` and `package_info_plus`.

### Measurement name and map records (1-to-1 Pins)

- `utils/measurement_name.dart` normalizes names by trimming whitespace and
  rejecting blank input.
- Every individual measurement with valid GPS coordinates is plotted as its
  own independent green pin marker (1 measurement = 1 point), labeled with
  its measurement name. Tapping a pin opens the measurement detail dialog.
- Duplicate GPS locations are fanned out slightly so every pin remains selectable.

### Local history, filter checkboxes, and AppBar export

- The dashboard History bottom sheet has live name search, date search, and a
  dedicated checkbox filter panel allowing users to tick "ทั้งหมด" (All),
  specific measurement names, or specific recorded dates.
- An **Export Raw Log** icon button (`Icons.file_download_outlined`) has been
  added directly to the AppBar next to the History icon.
- Tapping the export icon opens an export modal allowing users to choose the format
  (CSV with raw samples / JSON) and select records using the same checkbox system
  (All, by Name, by Date) before sharing/downloading.

### Responsive dashboard status

- **Portrait Layout:** Fits entirely within a single viewport without scrolling. Map
  takes flex 7, GPS bar and measurement name input are compact underneath, and the 8-card
  grid takes flex 10. The **START** button is a floating circle positioned directly at
  the intersection between the four cards (ไนโตรเจน, ฟอสฟอรัส, โพแทสเซียม, ความเค็ม). All
  four cards curve inward (`CornerCutoutClipper`) around the circular button.
- **Landscape Layout:** Map fills the left half and sensor grid (4 columns x 2 rows)
  fills the right pane. The **START** button is an enlarged floating half-circle dome
  (170x80) anchored at the bottom-center of the entire screen. Both the Map (bottom-right
  via `MapLandscapeClipper`) and Card 4 (bottom-left) curve inward around the dome.
- **Sensor Cards:** Bottom-left subtext has been removed. The numerical value is enlarged
  (`fontSize: 34`, bold) and centered both vertically and horizontally inside the white
  card, while its unit text is anchored at the bottom.

## Soil values and Data Hub entities

`services/home_assistant_service.dart` sends one `POST /api/ingest` per
measurement, with `device_id` and eight entries in `readings`:

| Entity ID | State | Unit |
| --- | --- | --- |
| `sensor.soil_ch340_temperature` | temperature, 2 decimal places | °C |
| `sensor.soil_ch340_moisture` | moisture | % |
| `sensor.soil_ch340_ec` | EC | µS/cm |
| `sensor.soil_ch340_salinity` | salinity | mg/L |
| `sensor.soil_ch340_nitrogen` | nitrogen | mg/kg |
| `sensor.soil_ch340_phosphorus` | phosphorus | mg/kg |
| `sensor.soil_ch340_potassium` | potassium | mg/kg |
| `sensor.soil_ch340_ph` | pH, 2 decimal places | none |

Each reading includes its own numeric `state`, the measurement name and UTC
timestamp, and attributes with the local log ID and GPS data when available.
In Data Hub, check **Device API → Devices and received entities** and the
history view for the matching device, measurement name, and time.

## Important source files

| File | Responsibility |
| --- | --- |
| `main.dart` | App entry point, routes, theme |
| `screens/dashboard_screen.dart` | Read flow, local log/map UI, sync trigger |
| `models/soil_measurement.dart` | Parsed sensor model, JSON/local persistence model |
| `services/measurement_engine.dart` | One-start/10-valid-sample collection and timeout logic |
| `services/device_identity_service.dart` | Persistent installation UUID and non-restricted device metadata |
| `services/usb_serial_service.dart` | CH340 discovery, Modbus requests and packet validation |
| `services/gps_service.dart` | Permissions and current GPS data |
| `services/local_storage_service.dart` | SharedPreferences local history (maximum 200 records) |
| `services/home_assistant_service.dart` | Home Assistant REST sensor updates |
| `utils/modbus_utils.dart` | Modbus request and CRC helpers |
| `utils/app_constants.dart` | USB constants, app constants, local-storage keys |

## Local-history and map rules

- Measurements are inserted at index 0 in local storage, so newest is first.
- Completed new records contain exactly 10 raw samples and averaged values;
  legacy records may contain zero raw samples and must remain untouched.
- Each GPS-enabled log owns one green marker. Do not restore proximity grouping
  or clustering; it would hide individual measurements.
- Do not add a second explicit save action unless deduplication is redesigned.

## Data Hub connection

- The dashboard settings menu saves the Device API URL and key on this device.
  The default URL is `http://192.168.6.223:8099/api/ingest`.
- Each completed measurement is saved locally, then posted once to Data Hub
  as JSON with Bearer authentication. Only a successful response marks it synced.
- Android network access and cleartext HTTP are enabled in
  `../android/app/src/main/AndroidManifest.xml`.
- Never put an access token in this document, commit message, logs, screenshots,
  or bug reports.

## Build and test

From the project root:

```powershell
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

For a dedicated local build, `data-hub.local.json` (ignored by Git)
can provide `DATA_HUB_URL` and `DATA_HUB_API_KEY`. This embeds the
defaults in that APK. Use the settings menu for distributed builds.

```powershell
flutter build apk --debug --dart-define-from-file=data-hub.local.json
```

The generated debug APK path is
`build\app\outputs\flutter-apk\app-debug.apk`.

### Last validation status (as of 2026-11-17; user-provided latest output)

- Focused Task 3–4 tests: PASS (9 tests): averaging, invalid-sample rejection,
  duplicate START prevention, timeout/cancel handling, JSON round-trip,
  backward compatibility, persistent UUID, and one-record de-duplication.
- Focused Task 5–6 tests: PASS (7 tests): blank-name rejection, Thai/English
  names, JSON name persistence, one-marker-per-measurement, nearby separation,
  exact-overlap selection offsets, and GPS absence.
- The latest pasted `flutter analyze` completed in 25.4 seconds with 62 issues:
  three unused declarations in app code and informational diagnostics in the
  bundled `packages/usb_serial`. The unused `_formatTime`, `_detailRow`, and
  `_markerLabel` declarations were removed. Analyzer has not been rerun after
  these removals and later UI edits. Do not suppress unrelated USB package
  diagnostics.
- The latest pasted `flutter test --reporter expanded` failed two tests:
  `measurement_name_map_test.dart` expected the newer GPS record, while the
  requirement anchors to the earliest valid GPS record; its expectation was
  corrected to the older record. `sensor_card_test.dart` expected the unit
  closer to the card edge than actual Card margin/padding; its expected
  coordinates were corrected. A successful rerun is not captured. The same run
  showed HTTP 400 requests from map tiles in the smoke test.
- Export tests in that run passed the CSV/JSON serialization tests and the new
  mocked share-parameters test (through test 15). Overall suite still failed due
  to the two tests above.
- User-reported `flutter build apk --debug`: PASS, generated
  `build\app\outputs\flutter-apk\app-debug.apk` in 254.5 seconds before
  subsequent UI/export/test changes. A fresh build has not been verified.
- No real CH340 hardware test has been performed. Verify Android permission,
  initialization, 10-sample completion, timeout, and reconnect behavior on the
  target device.

## Validation checklist

1. Install an APK built after the latest source changes.
2. Confirm the Android device can resolve/reach the Home Assistant host.
3. Connect the CH340 sensor and grant USB and location permissions.
4. Wait for **READY** after the three-second USB initialization.
5. Enter a non-empty measurement name, then tap **Read sensor** once and wait
   for the measurement spinner to finish.
6. Confirm exactly one new entry appears in local history and, if GPS is
   available, on the map. Confirm it has 10 raw samples in local JSON.
7. In Home Assistant, open **Developer Tools → States** and verify the
   `sensor.soil_ch340_*` entities update with distinct state values.
8. Confirm the named measurement has its own marker; for identical GPS points,
   confirm the fanned-out pins can each be tapped separately.

## Deprecated/removed integration

Firebase and Firestore are no longer part of the application. Do not restore
Firebase packages, `google-services.json`, or the Google Services Gradle plugin
unless the project explicitly returns to Firebase.
