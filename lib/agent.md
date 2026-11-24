# Meta Soil working context

Updated 2026-11-24 (Asia/Bangkok). The Android app is **1.5.7**, build **4**.

## Project

Meta Soil is a Flutter app for an 8-in-1 soil sensor connected through a CH340
USB-to-serial adapter. It collects Modbus RTU samples, displays and stores the
results locally, attaches GPS when available, and can send readings to Data Hub.

The workspace root is `D:\EVERYTHING_WHILE_INTERN\Application_intern001\soil_app`. Paths in this
document are relative to the repository root.

## Measurement and USB

- Android checks for the sensor on startup, attach/detach events, and when the
  app resumes. It identifies CH340 devices by vendor ID `0x1A86` or a product
  name containing `CH340`. The Android attach filter includes WCH products
  `0x5523`, `0x7522`, and `0x7523`.
- The bundled `usb_serial` plugin checks USB permission before opening the
  port. Connection attempts are single-flight. After a denial, replugging the
  sensor or choosing **Retry connection / ลองเชื่อมต่อใหม่** allows another
  request. The app opens the serial port at 9600 baud, 8N1.
- Warm-up takes about three seconds. It requires at least one CRC-valid Modbus
  response before the button enters the ready state. Warm-up samples are
  discarded. Disconnecting clears the session and stops active measurement.
- The ready button reads **กดเพื่อวัดค่า** or **Press / to measure**. The
  unavailable button reads **ยังไม่พร้อม** or **Not Ready**. Tapping it shows
  the current USB status, with the retry action when applicable.
- A nonempty measurement name is required. It is trimmed and locked during
  collection. The app shows a 10-second countdown and a centered progress
  dialog. Queries are spaced about 900 ms apart. `MeasurementEngine` accepts
  exactly 10 complete samples and has a separate 30-second timeout.
- Completion averages the eight readings, keeps the 10 raw samples together,
  and stores one record under a unique measurement ID. The app attempts to get
  a current GPS fix before saving and stores coordinates, accuracy, and GPS
  timestamp when available. The app waits up to four seconds for the fix,
  then saves the result without coordinates if the fix is unavailable.
- Local history uses SharedPreferences, newest first, with ID deduplication.
  When a new save exceeds the 200-record target, the oldest synced records are
  removed first. Pending records are retained, so the list can exceed 200.
  Older records with missing raw samples remain readable.
- Each installation has a persistent UUID. Device metadata includes platform,
  app version, hardware model, and OS version.

## Dashboard and appearance

| Layout | Map and cards | Measure button |
| --- | --- | --- |
| Phone portrait | Map, GPS, and a compact name field above a 2 × 4 grid | 120 × 58 dp half-circle centered below the cards, inside the safe area |
| Phone landscape | Map on the left near half the usable width, with GPS, a compact name field, and a 4 × 2 grid on the right | 86 × 42 dp button to the right of the name field |
| Tablet portrait | Map above a 2 × 4 grid, with corner cutouts around the button | 88 dp circle centered between the bottom two rows |
| Tablet landscape | Map on the left and 4 × 2 grid on the right, with a cutout at the bottom center | 132 × 64 dp half-circle at the bottom center |

- A shortest side below 480 logical pixels uses the phone layout. The phone
  dashboard can scroll when a short viewport or larger text needs more room.
  Sensor cards center their titles in portrait. Landscape puts the abbreviation
  on the first line and aligns the name below it on the left. The phone layout
  uses smaller labels and icons and reserves room for units. Long values scale
  down to fit while retaining all digits.
- The app bar has a white **TH / EN** control beside the export button. Thai
  and English labels and the language preference persist across restarts.
  The language-change dialog uses the language being left.
- IBM Plex Sans Thai is the default text font. Manrope is used for numeric
  readings, units, countdowns, and selected English text. Both are bundled
  with their licenses and have a `sans-serif` fallback.
- The app bar uses the full-color `assets/meta_soil_logo.png` on a white
  square with slightly rounded corners. The app bar background is
  `#103E3B`, the primary accent is `#167968`, and the dashboard background
  is `#E9EFEA`. See `lib/utils/app_constants.dart` for metric colors.

## Name history, map, and exports

- The name field shows up to 30 recently used measurement names. The history is
  initialized from existing logs, deduplicated, and stored on the device. The
  cross at the right of a suggestion removes it from name history.
- The map groups records by trimmed measurement name. A group with valid GPS
  coordinates gets one green pin, anchored at its earliest valid GPS reading.
  Pins for different names at an identical position are offset for tapping.
  Selecting a pin opens the date/time list for that name and then the individual
  measurement details.
- The trash action in a pin popup asks for confirmation. It removes those
  measurement IDs from map display on both map screens. Measurements remain
  available in Local Log, export, and the upload queue. A later measurement
  with the same name and valid GPS can create a new pin.
- Local Log supports live name/date search, name and date filters, per-record
  details, and local-history clearing after confirmation. Selecting names
  narrows the available dates to those names. When several names are selected,
  their dates are combined. Selections for dates that disappear are cleared.
- The Local Log filter panel starts with no selection on its first opening.
  Its bottom **Confirm / ยืนยัน** button is gray and disabled until the user
  selects a name, date, or **All / ทั้งหมด**. Closing the filter panel discards
  edits made since the last confirmation.
- **Export raw logs / ส่งออกข้อมูลดิบ** supports CSV with raw samples and full
  JSON through Android sharing. The export dialog initially selects all
  records. After clearing **All**, the same name-to-date rules apply. With
  zero matches, the button shows **Export 0 items / ส่งออก 0 รายการ** and is
  disabled.
- On a short viewport, Local Log can scroll the header, search, filters, and
  records together and adjusts for the keyboard. Confirm stays at the bottom
  when space permits and scrolls into reach otherwise. The export dialog also
  scrolls its header and action when space is limited.

## Data Hub

- Enter `config555` in the measurement-name field and submit to open the
  Device API settings. There is no settings icon. Credentials are stored per
  device, and the dialog provides a connection test that posts a test reading.
- The build default endpoint is `http://192.168.6.223:8099/api/ingest`. The
  build default key is empty unless supplied locally. Enter deployment
  credentials in the app. Keep keys out of the repository, APKs intended for
  distribution, logs, screenshots, and documentation.
- New measurements are saved locally before upload. On a new installation,
  automatic uploads default to off. The Local Log switch next to the filter
  immediately saves the selected mode.
- With automatic uploads enabled and the app running, the queue starts about
  seven seconds after the Android default network becomes available. It sends
  the oldest pending record first, one at a time. A network change restarts
  the delay. On a temporary send failure the auto queue can retry after about
  30 seconds. A permanent HTTP rejection stops that run. Only an accepted
  response marks the record synced, and unsuccessful records stay pending.
- **Send pending items / ส่งรายการค้าง** works with either mode. On Android,
  the button is gray and disabled without a validated internet connection,
  including Wi-Fi without internet. Automatic scheduling uses the default
  network handle, which can also support a locally reachable Data Hub.
- `lib/services/home_assistant_service.dart` retains its original filename.
  It sends a Bearer-authenticated Data Hub ingest request with `device_id`
  and eight separate `readings` entries per measurement. Each entry has a
  numeric state, name, UTC timestamp, local log ID, and GPS attributes when
  available. Android cleartext HTTP is enabled for local deployments.

| Entity suffix after `sensor.soil_ch340_` | Unit |
| --- | --- |
| `temperature` | °C |
| `moisture` | % |
| `ec` | µS/cm |
| `salinity` | mg/L |
| `nitrogen` | mg/kg |
| `phosphorus` | mg/kg |
| `potassium` | mg/kg |
| `ph` | unitless |

## Change history

The revisions below follow the order of work. Several iterations were
consolidated into the same Git commit.

| Round | Changes |
| --- | --- |
| Initial app and map, 10–13 Nov | Set up the Flutter app, added the map, and iterated on the dashboard and device UI. The initial and map milestones are `ba5dd92` and `6a5e2cd`. |
| Sensor, storage, and Data Hub baseline, 18 Nov | Established USB warm-up and the 10-sample measurement flow, local history, device identity, Data Hub ingest, search and export, and Meta Soil branding. Removed Firebase, Firestore, and the Google Services Gradle integration. The baseline is recorded in `18f2cb0`. |
| Name history and hidden settings, 19 Nov | Added a dropdown of previous names with individual removal, moved Data Hub settings behind `setting_API`, and later changed the command to `config555`. Disabled export when the record count is zero. |
| Measurement UI and translations, 19 Nov | Added ready and unavailable labels, measurement countdown and progress dialog, and a centered USB-status dialog. Added Thai/English selection. Changed the language control from flags to bold white **TH / EN** and localized the export label and all metric names. |
| Dashboard visual refinements, 19 Nov | Split the English measure label into two lines. Landscape headings first moved right, then left, and ultimately used a separate abbreviation line. Moved and reduced landscape icons, kept portrait headings centered, removed measure-button shadows, and darkened the dashboard background slightly. |
| Log and Data Hub queue, 19 Nov | Narrowed date choices by selected name while retaining Log search. Added manual and automatic upload modes with a seven-second network delay, moved the switch from settings to Local Log beside the filter, and disabled the manual send button when Android reports no validated internet. |
| Export, map, and typography, 19 Nov | Applied the same dependent date filters to export. Added confirmed pin removal with local records retained. Moved the Log filter confirmation to the bottom and disabled it until a selection exists. Bundled IBM Plex Sans Thai and Manrope. These revisions are consolidated in `0935419`. |
| First phone layout, 20 Nov | Added a dedicated compact layout after testing RMX2001. Separated titles, icons, numbers, and units and placed the measure action beside the name field. Committed as `7647635`. |
| Phone layout refinement, 20 Nov | Tried the tablet-style button positions on phones with smaller controls and automatic number scaling. The next revision moved the phone landscape button next to the name and put the phone portrait half-circle beneath the cards. Enlarged the portrait button from 92 × 44 to 102 × 49 and then 120 × 58 dp. Widened the landscape button from 74 to 86 dp. |
| USB retry and device rollout, 20 Nov | Added Android attach filters, explicit USB permission checks, resume detection, and an in-app retry. RMX2001 reported OTG off while connected to the PC. Installed the app on OPPO A60 and verified that Data Hub credentials were stored on that device. |
| Short landscape sheets, 20 Nov | Fixed the Local Log bottom overflow when the panel shrinks or the search keyboard opens. Added a short-screen export path so its action remains reachable. |
| Meta Soil 1.5.5, 20 Nov | Set version `1.5.5+2`. Tried a white logo on a green circle, then switched to the full-color original on a white rounded square after visual review. Installed the final build and checked the app-bar logo on Galaxy Tab A9. These latest revisions are consolidated in `24bfd7e`. |
| Meta Soil 1.5.7, 24 Nov | Set the bug-fix patch version to `1.5.7+4`. Limited the GPS wait when saving, isolated USB request timers, skipped corrupt local history rows, corrected date ordering in filters, and kept export selections after dismissing Android Share. |

## Main source files

| Path | Responsibility |
| --- | --- |
| `lib/main.dart`, `lib/utils/app_language.dart`, `lib/utils/app_fonts.dart` | Theme, fonts, localization, and routes |
| `lib/screens/dashboard_screen.dart`, `lib/widgets/sensor_card.dart` | Responsive dashboard, measurement flow, and upload queue |
| `lib/services/usb_serial_service.dart`, `packages/usb_serial/`, `android/app/src/main/res/xml/usb_sensor_filter.xml` | USB discovery, access, and serial communication |
| `lib/services/measurement_engine.dart`, `lib/models/soil_measurement.dart` | Sample collection and record structure |
| `lib/services/local_storage_service.dart`, `lib/services/measurement_name_history_service.dart` | Local persistence and recent names |
| `lib/utils/measurement_map_utils.dart`, `lib/services/map_pin_visibility.dart`, `lib/widgets/measurement_group_popup.dart` | Map grouping, pin visibility, and details |
| `lib/widgets/local_history_sheet.dart`, `lib/widgets/export_dialog.dart`, `lib/utils/history_filters.dart` | Logs, exports, and filters |
| `lib/services/measurement_export_service.dart`, `lib/services/home_assistant_service.dart` | File generation and Data Hub ingest |
| `android/app/src/main/kotlin/com/soil/sensor/soil_app/MainActivity.kt` | Android network state stream |

## Build and verification

Run these commands from the repository root.

```powershell
flutter pub get
flutter analyze
flutter test --no-pub --reporter expanded
flutter build apk --debug --no-pub
adb devices -l
adb -s <device-serial> install -r build/app/outputs/flutter-apk/app-debug.apk
```

The APK is `build/app/outputs/flutter-apk/app-debug.apk`. The `-r` option
preserves app data and device-specific Data Hub settings during an update.
An ignored `data-hub.local.json` may hold local values for `DATA_HUB_URL` and
`DATA_HUB_API_KEY`. Passing it with `--dart-define-from-file` embeds the
values at build time. Use in-app configuration for shared APKs.

- The full Flutter suite passed all 51 tests on 2026-11-24, including GPS
  timeout, USB request timing, corrupt history rows, and cross-year filters.
- The 1.5.7 debug build installed over the previous version and launched
  on Galaxy Tab A9 on 2026-11-24. Android reported version name `1.5.7`
  and build number `4`. The installed APK hash matched the built file.
- The 1.5.6 debug build installed over the previous version and launched
  on Galaxy Tab A9 on 2026-11-24. Android reported version name `1.5.6`
  and build number `3`. The installed APK hash matched the built file.
- The final 1.5.5 debug build installed and launched on Galaxy Tab A9. Android
  reported version name `1.5.5` and build number `2`. The white rounded logo
  was visually checked on that device.
- Earlier phone builds installed on RMX2001 and OPPO A60. The overflow fix was
  installed and launched on OPPO A60. The USB connection dropped during
  follow-up inspection, so the short landscape drag and keyboard cases were
  verified with Flutter widget tests.
- A complete physical run with the latest CH340 build and live Data Hub ingest
  remains unverified. To check it, enable OTG where required, attach the sensor,
  allow USB access, wait for the ready state, and measure once. Confirm one Log
  record with ten raw samples and check the matching eight readings in Data Hub.

## Follow-up ideas

- Add local backup and restore.
- Add per-plot trend graphs.
