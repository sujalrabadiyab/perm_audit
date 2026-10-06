# perm_audit

Find out which **sensitive Android permissions and services** actually end up in your Flutter app, and **which dependency added them**.

Your own `AndroidManifest.xml` is only part of the story. During the build, Gradle merges in the manifests of every plugin you use. `perm_audit` reads the final merged manifest, so you see what ships to users.

## What it checks

| Category | Permissions |
|---|---|
| Location | `ACCESS_BACKGROUND_LOCATION` |
| Contacts & accounts | `READ_CONTACTS`, `WRITE_CONTACTS`, `GET_ACCOUNTS` |
| Phone & calls | `READ_PHONE_STATE`, `READ_PHONE_NUMBERS`, `CALL_PHONE`, `ANSWER_PHONE_CALLS`, `READ_CALL_LOG`, `WRITE_CALL_LOG`, `PROCESS_OUTGOING_CALLS`, `ADD_VOICEMAIL`, `USE_SIP`, `ACCEPT_HANDOVER` |
| SMS | `SEND_SMS`, `RECEIVE_SMS`, `READ_SMS`, `RECEIVE_WAP_PUSH`, `RECEIVE_MMS` |
| Calendar | `READ_CALENDAR`, `WRITE_CALENDAR` |
| Storage & media | `READ_MEDIA_IMAGES`, `READ_MEDIA_VIDEO`, `READ_MEDIA_AUDIO`, `READ_MEDIA_VISUAL_USER_SELECTED`, `MANAGE_EXTERNAL_STORAGE` |
| Sensors & activity | `BODY_SENSORS`, `BODY_SENSORS_BACKGROUND`, `ACTIVITY_RECOGNITION` |
| Special / restricted | `SYSTEM_ALERT_WINDOW`, `REQUEST_INSTALL_PACKAGES`, `QUERY_ALL_PACKAGES`, `BIND_ACCESSIBILITY_SERVICE`, `BIND_DEVICE_ADMIN`, `WRITE_SETTINGS`, `SCHEDULE_EXACT_ALARM`, `USE_EXACT_ALARM`, `USE_FULL_SCREEN_INTENT`, `PACKAGE_USAGE_STATS`, `READ_LOGS`, all `FOREGROUND_SERVICE_*` types |

It also flags services that declare a `foregroundServiceType`, and services or receivers that require `BIND_ACCESSIBILITY_SERVICE` or `BIND_DEVICE_ADMIN`.

## Install

You only need the Dart SDK, which comes with Flutter. Install once per machine:

```bash
dart pub global activate perm_audit
```

If the `perm_audit` command isn't found, add the pub cache `bin` folder to your PATH:

- **Windows:** `%LOCALAPPDATA%\Pub\Cache\bin`
- **macOS / Linux:** `~/.pub-cache/bin`

To update later, run the same command again.

## Usage

Run these from your Flutter project root:

```bash
flutter build apk --release
perm_audit
```

The tool needs a finished build, because the merged manifest is only generated during one.

### Example output

```
⚠️  1 watched permission(s)/declaration(s) found in the final manifest (release):

[Special / restricted]
  - foregroundServiceType=location  (com.baseflow.geolocator.GeolocatorLocationService)
      type: foreground service | added by: :geolocator_android
      to remove: <service android:name="com.baseflow.geolocator.GeolocatorLocationService" tools:node="remove"/>
```

If nothing is found, it prints `✅ None of the watched permissions are present in the final manifest.`

### Options

| Option | Description |
|---|---|
| `--variant <name>` | Build variant or flavor to audit (default: `release`) |
| `--project <path>` | Flutter project root (default: current folder) |
| `--manifest <path>` | Audit a specific merged `AndroidManifest.xml` |
| `--report <path>` | Path to the manifest-merger report (for the "added by" column) |
| `--json <file>` | Also write the findings to a JSON file |
| `--fail` | Exit with code 1 if anything is found (for CI) |

## Removing something you don't need

Each finding prints a ready-made line. Add it inside the `<manifest>` tag of `android/app/src/main/AndroidManifest.xml`, and make sure the root tag declares the `tools` namespace:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:tools="http://schemas.android.com/tools">

    <uses-permission android:name="android.permission.READ_PHONE_STATE" tools:node="remove"/>

</manifest>
```

Removing a permission or service disables whatever plugin feature depends on it, so test the app afterwards.

## Use in CI

```yaml
- run: flutter build apk --release
- run: dart pub global activate perm_audit
- run: perm_audit --fail
```

The build fails if any watched permission appears, for example after a plugin update.

## Limitations

- It reports what is **declared** in the manifest. It can't tell whether your Dart code ever requests a permission at runtime.
- It only audits Android. For iOS, check `Info.plist` and entitlements separately.
- Each flavor or build type has its own merged manifest, so audit every variant you ship.
- The "added by" column depends on the manifest-merger report. If it shows `unknown`, check the report under `build/app/outputs/logs/`.

## License

MIT. See [LICENSE](LICENSE).