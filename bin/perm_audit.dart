// Flags sensitive/restricted Android permissions in the FINAL (merged) manifest
// of a Flutter/Android app and shows which dependency added each one.
//
// No packages needed. Dart ships with the Flutter SDK.
//
// Install once:  dart pub global activate --source git <repo-url>
//                (or: dart pub global activate --source path .)
// Usage (from any Flutter project root):
//         flutter build apk --release
//         perm_audit
//         perm_audit --variant debug
//         perm_audit --fail          (CI: exit 1 if found)
//         perm_audit --json report.json
//         perm_audit --manifest path/to/AndroidManifest.xml

import 'dart:convert';
import 'dart:io';

const watchlist = <String, List<String>>{
  'Location': ['ACCESS_BACKGROUND_LOCATION'],
  'Contacts & accounts': ['READ_CONTACTS', 'WRITE_CONTACTS', 'GET_ACCOUNTS'],
  'Phone & calls': [
    'READ_PHONE_STATE',
    'READ_PHONE_NUMBERS',
    'CALL_PHONE',
    'ANSWER_PHONE_CALLS',
    'READ_CALL_LOG',
    'WRITE_CALL_LOG',
    'PROCESS_OUTGOING_CALLS',
    'ADD_VOICEMAIL',
    'USE_SIP',
    'ACCEPT_HANDOVER',
  ],
  'SMS': [
    'SEND_SMS',
    'RECEIVE_SMS',
    'READ_SMS',
    'RECEIVE_WAP_PUSH',
    'RECEIVE_MMS'
  ],
  'Calendar': ['READ_CALENDAR', 'WRITE_CALENDAR'],
  'Storage & media': [
    'READ_MEDIA_IMAGES',
    'READ_MEDIA_VIDEO',
    'READ_MEDIA_AUDIO',
    'READ_MEDIA_VISUAL_USER_SELECTED',
    'MANAGE_EXTERNAL_STORAGE',
  ],
  'Sensors & activity': [
    'BODY_SENSORS',
    'BODY_SENSORS_BACKGROUND',
    'ACTIVITY_RECOGNITION'
  ],
  'Special / restricted': [
    'SYSTEM_ALERT_WINDOW',
    'REQUEST_INSTALL_PACKAGES',
    'QUERY_ALL_PACKAGES',
    'BIND_ACCESSIBILITY_SERVICE',
    'BIND_DEVICE_ADMIN',
    'WRITE_SETTINGS',
    'SCHEDULE_EXACT_ALARM',
    'USE_EXACT_ALARM',
    'USE_FULL_SCREEN_INTENT',
    'PACKAGE_USAGE_STATS',
    'READ_LOGS',
  ],
};

// FOREGROUND_SERVICE_* (all types) matched by prefix.
const prefixWatch = {
  'Special / restricted': ['FOREGROUND_SERVICE_']
};

// Normally declared as android:permission="..." on a <service>/<receiver>.
const componentPerms = {'BIND_ACCESSIBILITY_SERVICE', 'BIND_DEVICE_ADMIN'};

final lookup = {
  for (final e in watchlist.entries)
    for (final n in e.value) n: e.key,
};

String short(String n) => n.split('.').last;

String? classify(String name) {
  final s = short(name);
  if (lookup.containsKey(s)) return lookup[s];
  for (final e in prefixWatch.entries) {
    if (e.value.any(s.startsWith)) return e.key;
  }
  return null;
}

Map<String, String> attrs(String raw) => {
      for (final m in RegExp(r'([\w:.\-]+)\s*=\s*"([^"]*)"').allMatches(raw))
        m.group(1)!: m.group(2)!,
    };

/// Maps "uses-permission#android.permission.X" -> contributing sources.
Map<String, Set<String>> parseReport(File f) {
  final out = <String, Set<String>>{};
  if (!f.existsSync()) return out;
  String? current;
  final srcLine = RegExp(r'^\s*(ADDED|MERGED) from');
  final skip = RegExp(r'^(ADDED|MERGED|REJECTED|INJECTED)');
  for (final line in f.readAsLinesSync()) {
    final isHeader = line.isNotEmpty &&
        !line.startsWith(RegExp(r'\s')) &&
        !skip.hasMatch(line) &&
        line.contains('#') &&
        !line.startsWith('-- ') &&
        !line.startsWith('Merging') &&
        !line.startsWith('=');
    if (isHeader) {
      current = line.trim();
      out.putIfAbsent(current, () => {});
    } else if (current != null && srcLine.hasMatch(line)) {
      final m = RegExp(r'from \[([^\]]+)\]').firstMatch(line);
      if (m != null) {
        out[current]!.add(m.group(1)!);
      } else if (line.contains('src/main') || line.contains('/android/app/')) {
        out[current]!.add('(your app)');
      } else {
        final t = line.split('from').last.trim();
        out[current]!.add(t.length > 80 ? t.substring(0, 80) : t);
      }
    }
  }
  return out;
}

File? findManifest(String project, String variant) {
  final direct = File(
      '$project/build/app/intermediates/merged_manifests/$variant/AndroidManifest.xml');
  if (direct.existsSync()) return direct;
  final base = Directory('$project/build/app/intermediates');
  if (!base.existsSync()) return null;
  for (final e in base.listSync(recursive: true, followLinks: false)) {
    if (e is File &&
        e.path.endsWith('AndroidManifest.xml') &&
        e.path.contains('merged_manifest') &&
        e.path.toLowerCase().contains(variant.toLowerCase())) {
      return e;
    }
  }
  return null;
}

void main(List<String> argv) {
  String project = '.', variant = 'release';
  String? manifestPath, reportPath, jsonPath;
  var fail = false;
  for (var i = 0; i < argv.length; i++) {
    switch (argv[i]) {
      case '--project':
        project = argv[++i];
        break;
      case '--variant':
        variant = argv[++i];
        break;
      case '--manifest':
        manifestPath = argv[++i];
        break;
      case '--report':
        reportPath = argv[++i];
        break;
      case '--json':
        jsonPath = argv[++i];
        break;
      case '--fail':
        fail = true;
        break;
      default:
        stderr.writeln('Unknown option: ${argv[i]}');
        exit(2);
    }
  }

  final manifest = manifestPath != null
      ? File(manifestPath)
      : findManifest(project, variant);
  if (manifest == null || !manifest.existsSync()) {
    stderr.writeln('Merged manifest not found. Run '
        '"flutter build apk --$variant" first, or pass --manifest.');
    exit(2);
  }
  final report = File(reportPath ??
      '$project/build/app/outputs/logs/manifest-merger-$variant-report.txt');
  final sources = parseReport(report);

  final xml = manifest
      .readAsStringSync()
      .replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');
  final findings = <Map<String, dynamic>>[];

  final tagRe = RegExp(
      r'<(uses-permission-sdk-23|uses-permission|service|receiver)\b([^>]*?)/?>',
      dotAll: true);
  for (final m in tagRe.allMatches(xml)) {
    final tag = m.group(1)!;
    final a = attrs(m.group(2)!);
    final name = a['android:name'] ?? '';
    if (tag.startsWith('uses-permission')) {
      final cat = classify(name);
      if (cat != null) {
        findings.add({
          'category': cat,
          'permission': short(name),
          'kind': 'uses-permission',
          'via': '',
          'remove': '<$tag android:name="$name" tools:node="remove"/>',
          'sources': (sources['$tag#$name'] ?? {}).toList()..sort(),
        });
      }
    } else {
      final perm = short(a['android:permission'] ?? '');
      if (componentPerms.contains(perm)) {
        findings.add({
          'category': lookup[perm]!,
          'permission': perm,
          'kind': '$tag declaration',
          'via': name,
          'remove': '<$tag android:name="$name" tools:node="remove"/>',
          'sources': (sources['$tag#$name'] ?? {}).toList()..sort(),
        });
      }
      final fgs = a['android:foregroundServiceType'];
      if (tag == 'service' && fgs != null) {
        findings.add({
          'category': 'Special / restricted',
          'permission': 'foregroundServiceType=$fgs',
          'kind': 'foreground service',
          'via': name,
          'remove': '<service android:name="$name" tools:node="remove"/>',
          'sources': (sources['service#$name'] ?? {}).toList()..sort(),
        });
      }
    }
  }

  if (findings.isEmpty) {
    print(
        '\u2705 None of the watched permissions are present in the final manifest.');
    return;
  }

  print('\u26a0\ufe0f  ${findings.length} watched permission(s)/declaration(s) '
      'found in the final manifest ($variant):\n');
  for (final cat in watchlist.keys) {
    final rows = findings.where((f) => f['category'] == cat).toList()
      ..sort((a, b) =>
          (a['permission'] as String).compareTo(b['permission'] as String));
    if (rows.isEmpty) continue;
    print('[$cat]');
    for (final f in rows) {
      final src = (f['sources'] as List).isEmpty
          ? (sources.isEmpty ? 'unknown (no merger report)' : 'unknown')
          : (f['sources'] as List).join(', ');
      final via = (f['via'] as String).isEmpty ? '' : '  (${f['via']})';
      print('  - ${f['permission']}$via\n'
          '      type: ${f['kind']} | added by: $src\n'
          '      to remove: ${f['remove']}');
    }
    print('');
  }
  print('To remove an item: add its "to remove" line inside <manifest> in\n'
      'android/app/src/main/AndroidManifest.xml, and make sure the root tag has:\n'
      '  xmlns:tools="http://schemas.android.com/tools"\n'
      'Note: removing a plugin\'s service/permission disables the plugin feature that needs it.');

  if (jsonPath != null) {
    File(jsonPath).writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(findings));
  }
  if (fail) exit(1);
}
