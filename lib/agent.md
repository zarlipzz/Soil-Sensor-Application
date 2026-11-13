# Soil App: working context

## Purpose

Flutter Android application for a CH340 USB Modbus RTU **8-in-1 soil sensor**.
It reads a sensor packet, attaches the device GPS position, displays the live
values, stores a local history, and updates Home Assistant sensor entities.

Workspace root: `D:\Application_intern001\soil_app`  
This file is in `lib`, so paths below are relative to `lib/` unless noted.

## Current behavior

1. User taps the single **read sensor** button.
2. `UsbSerialService` sends a Modbus command and validates the reply.
3. `SoilMeasurement.fromRawBytes` parses the reading and creates its log ID and
   timestamp.
4. `GpsService` supplies latitude, longitude, accuracy, and location time when
   available.
5. `DashboardScreen._processNewMeasurement` saves the reading locally and then
   calls `HomeAssistantService.uploadMeasurement`.
6. Home Assistant receives one REST state update per soil measurement. The
   local log is marked synced only if every state update succeeds.

There is intentionally no separate save button: a reading is saved and synced
once, preventing duplicate history entries.

## Soil values and Home Assistant entities

`services/home_assistant_service.dart` calls Home Assistant's REST endpoint
`POST /api/states/<entity_id>` for these entities:

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
| `sensor.soil_ch340_gps` | `latitude, longitude` | none; only when GPS exists |

Every entity shares attributes from the same reading: `device_id`, `recorded_at`,
`local_log_id`, plus GPS latitude, longitude, accuracy, and GPS timestamp when
available. This is why attributes look similar across sensors; each entity's
**state** is its own value.

In Home Assistant, inspect the current entities at **Developer Tools → States**
by searching `soil_ch340`. Add these entities to an Entities card or History
Graph card to display them in a dashboard.

## Important source files

| File | Responsibility |
| --- | --- |
| `main.dart` | App entry point, routes, theme |
| `screens/dashboard_screen.dart` | Read flow, local log/map UI, sync trigger |
| `models/soil_measurement.dart` | Parsed sensor model, JSON/local persistence model |
| `services/usb_serial_service.dart` | CH340 discovery, Modbus requests and packet validation |
| `services/gps_service.dart` | Permissions and current GPS data |
| `services/local_storage_service.dart` | SharedPreferences local history (maximum 200 records) |
| `services/home_assistant_service.dart` | Home Assistant REST sensor updates |
| `utils/modbus_utils.dart` | Modbus request and CRC helpers |
| `utils/app_constants.dart` | USB constants, app constants, local-storage keys |

## Local-history and map rules

- Measurements are inserted at index 0 in local storage, so newest is first.
- Logs are grouped by nearby GPS coordinates in `DashboardScreen`.
- Tapping a green grouped map pin sorts the group by descending timestamp before
  presenting it, so the latest item is always at the top.
- Do not add a second explicit save action unless deduplication is redesigned.

## Home Assistant connection and security

- The Home Assistant base URL is configured in `HomeAssistantService`; the
  current intended server is `http://labubu.local`.
- Android network access and cleartext HTTP are enabled in
  `../android/app/src/main/AndroidManifest.xml`.
- The service currently contains an access token fallback so a manually built
  APK can connect without build flags. This is unsafe for an APK or source code
  shared with anyone else. Prefer build-time `--dart-define` values or a server
  proxy, and revoke/regenerate exposed tokens before distribution.
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

To override the Home Assistant settings without editing source:

```powershell
flutter build apk --debug `
  --dart-define=HOME_ASSISTANT_URL=http://your-home-assistant-host `
  --dart-define=HOME_ASSISTANT_TOKEN=YOUR_LONG_LIVED_TOKEN
```

The generated debug APK path is
`build\app\outputs\flutter-apk\app-debug.apk`.

## Validation checklist

1. Install an APK built after the latest source changes.
2. Confirm the Android device can resolve/reach the Home Assistant host.
3. Connect the CH340 sensor and grant USB and location permissions.
4. Tap **read sensor** once.
5. Confirm a new entry appears in local history and, if GPS is available, on
   the map.
6. In Home Assistant, open **Developer Tools → States** and verify the
   `sensor.soil_ch340_*` entities update with distinct state values.

## Deprecated/removed integration

Firebase and Firestore are no longer part of the application. Do not restore
Firebase packages, `google-services.json`, or the Google Services Gradle plugin
unless the project explicitly returns to Firebase.
