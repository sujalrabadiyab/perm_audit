// Flags sensitive/restricted Android permissions in the FINAL (merged) manifest
// of a Flutter/Android app and shows which dependency added each one.
//
// No packages needed. Dart ships with the Flutter SDK.
//
// Install once:  dart pub global activate perm_audit
// Usage (from the Flutter project root, after a build):
//         flutter build apk --release
//         perm_audit
//         dart pub global run perm_audit      (same thing, no PATH needed)
//
// Run "perm_audit --help" for all options.

import 'dart:convert';
import 'dart:io';

const _usage = '''
perm_audit - list sensitive Android permissions in a Flutter app merged manifest

Usage: perm_audit [options]
Run from the Flutter project root, after building the app.

Options:
  --variant <name>   Build variant or flavor to audit (default: release)
  --project <path>   Flutter project root (default: current folder)
  --manifest <path>  Audit a specific merged AndroidManifest.xml
  --report <path>    Manifest-merger report (for the "added by" column)
  --json <file>      Also write the findings to a JSON file
  --fail             Exit with code 1 if anything is found (for CI)
  -h, --help         Show this help

Exit codes:
  0  Finished (findings do not fail the run unless --fail is given)
  1  Findings present and --fail was given
  2  Usage error, or merged manifest not found
''';

const _androidPrefix = 'android.permission.';
const _voicemailAdd = 'com.android.voicemail.permission.ADD_VOICEMAIL';

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
    'RECEIVE_MMS',
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
    'ACTIVITY_RECOGNITION',
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
const prefixWatch = <String, List<String>>{
  'Special / restricted': ['FOREGROUND_SERVICE_'],
};

// Normally declared as android:permission="..." on a <service>/<receiver>.
const componentPerms = <String>{
  'BIND_ACCESSIBILITY_SERVICE',
  'BIND_DEVICE_ADMIN',
};

final Map<String, String> lookup = {
  for (final e in watchlist.entries)
    for (final n in e.value) n: e.key,
};

/// Returns the short permission name for platform permissions only.
/// A custom permission such as "com.example.permission.READ_CONTACTS" is
/// not the platform permission and returns null.
String? shortName(String name) {
  if (name == _voicemailAdd) return 'ADD_VOICEMAIL';
  if (name.startsWith(_androidPrefix)) {
    return name.substring(_androidPrefix.length);
  }
  return null;
}

String? classify(String name) {
  final s = shortName(name);
  if (s == null) return null;
  final direct = lookup[s];
  if (direct != null) return direct;
  for (final e in prefixWatch.entries) {
    if (e.value.any(s.startsWith)) return e.key;
  }
  return null;
}

// Attribute values may use double or single quotes.
final RegExp _attrRe =
    RegExp(r"([\w:.\-]+)\s*=\s*(?:\x22([^\x22]*)\x22|'([^']*)')");

// An opening tag. Quoted attribute values may contain ">" safely.
final RegExp _tagRe = RegExp(
  r"<(uses-permission-sdk-23|uses-permission|service|receiver)\b"
  r"((?:[^>\x22']|\x22[^\x22]*\x22|'[^']*')*)>",
);

final RegExp _commentRe = RegExp(r'<!--.*?-->', dotAll: true);

Map<String, String> attrs(String raw) => {
      for (final m in _attrRe.allMatches(raw))
        m.group(1)!: m.group(2) ?? m.group(3) ?? '',
    };

final RegExp _headerRe = RegExp(r'^[A-Za-z][\w\-]*#\S');
final RegExp _sourceRe = RegExp(r'^\s*(?:ADDED|MERGED) from\s*(.*)$');
final RegExp _bracketRe = RegExp(r'^\[([^\]]+)\]');
final RegExp _appSrcRe = RegExp(r'[/\\]android[/\\]app[/\\]src[/\\]');

/// Maps "uses-permission#android.permission.X" -> contributing sources.
Map<String, Set<String>> parseReport(File f) {
  final out = <String, Set<String>>{};
  if (!f.existsSync()) return out;
  String? current;
  for (final line in f.readAsLinesSync()) {
    final src = _sourceRe.firstMatch(line);
    if (src != null) {
      if (current == null) continue;
      final rest = src.group(1)!.trim();
      final bracket = _bracketRe.firstMatch(rest);
      if (bracket != null) {
        out[current]!.add(bracket.group(1)!);
      } else if (_appSrcRe.hasMatch(rest)) {
        out[current]!.add('(your app)');
      } else if (rest.isNotEmpty) {
        out[current]!.add(
          rest.length > 80 ? '${rest.substring(0, 77)}...' : rest,
        );
      }
    } else if (_headerRe.hasMatch(line)) {
      current = line.trim();
      out.putIfAbsent(current, () => <String>{});
    }
  }
  return out;
}

File? _manifestIn(Directory dir) {
  final direct = File('${dir.path}/AndroidManifest.xml');
  if (direct.existsSync()) return direct;
  final found = dir
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()
      .where((f) => f.path.endsWith('AndroidManifest.xml'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  return found.isEmpty ? null : found.first;
}

/// Finds the merged manifest for [variant] (exact, case-insensitive match).
/// Variant folder names seen along the way are added to [available].
File? findManifest(String buildDir, String variant, List<String> available) {
  final want = variant.toLowerCase();
  File? result;
  for (final folder in const ['merged_manifests', 'merged_manifest']) {
    final base = Directory('$buildDir/intermediates/$folder');
    if (!base.existsSync()) continue;
    final dirs = base.listSync(followLinks: false).whereType<Directory>();
    for (final d in dirs) {
      final name = d.path.split(RegExp(r'[/\\]')).last;
      if (!available.contains(name)) available.add(name);
      if (result == null && name.toLowerCase() == want) {
        result = _manifestIn(d);
      }
    }
    if (result != null) break;
  }
  available.sort();
  return result;
}

/// Advisory only: the build output may predate recent project changes.
void _warnIfStale(File manifest, String project) {
  final built = manifest.lastModifiedSync();
  final inputs = [
    '$project/pubspec.yaml',
    '$project/pubspec.lock',
    '$project/android/app/src/main/AndroidManifest.xml',
  ];
  for (final path in inputs) {
    final f = File(path);
    if (f.existsSync() && f.lastModifiedSync().isAfter(built)) {
      stderr.writeln('Warning: $path is newer than the merged manifest. '
          'The report may be out of date; rebuild to be sure.');
      return;
    }
  }
}

int _usageError(String message) {
  stderr.writeln('perm_audit: $message');
  stderr.writeln('Run "perm_audit --help" for usage.');
  return 2;
}

int run(List<String> argv) {
  var project = '.';
  var variant = 'release';
  String? manifestPath;
  String? reportPath;
  String? jsonPath;
  var failOnFound = false;

  const needsValue = {
    '--project',
    '--variant',
    '--manifest',
    '--report',
    '--json',
  };

  var i = 0;
  while (i < argv.length) {
    var arg = argv[i];
    String? inline;
    final eq = arg.indexOf('=');
    if (arg.startsWith('--') && eq != -1) {
      inline = arg.substring(eq + 1);
      arg = arg.substring(0, eq);
    }

    String? value;
    if (needsValue.contains(arg)) {
      if (inline != null) {
        value = inline;
      } else if (i + 1 < argv.length) {
        i++;
        value = argv[i];
      }
      if (value == null || value.isEmpty) {
        return _usageError('Missing value for $arg');
      }
    }

    switch (arg) {
      case '-h':
      case '--help':
        print(_usage);
        return 0;
      case '--project':
        project = value!;
        break;
      case '--variant':
        variant = value!;
        break;
      case '--manifest':
        manifestPath = value!;
        break;
      case '--report':
        reportPath = value!;
        break;
      case '--json':
        jsonPath = value!;
        break;
      case '--fail':
        failOnFound = true;
        break;
      default:
        return _usageError('Unknown option: ${argv[i]}');
    }
    i++;
  }

  final buildDir = '$project/build/app';
  final available = <String>[];
  final File? manifest = manifestPath != null
      ? File(manifestPath)
      : findManifest(buildDir, variant, available);

  if (manifest == null || !manifest.existsSync()) {
    if (manifestPath != null) {
      stderr.writeln('perm_audit: manifest not found: $manifestPath');
    } else {
      stderr.writeln('perm_audit: no merged manifest found for variant '
          '"$variant" in $buildDir.');
      if (available.isEmpty) {
        stderr.writeln('Build the app first, e.g. '
            '"flutter build apk --$variant", or pass --manifest.');
      } else {
        stderr.writeln('Available variants: ${available.join(', ')}. '
            'Pick one with --variant.');
      }
    }
    return 2;
  }
  if (manifestPath == null) _warnIfStale(manifest, project);

  final report = File(reportPath ??
      '$buildDir/outputs/logs/manifest-merger-$variant-report.txt');
  final sources = parseReport(report);
  List<String> sourcesFor(String key) =>
      (sources[key] ?? const <String>{}).toList()..sort();

  final xml = manifest.readAsStringSync().replaceAll(_commentRe, '');
  final findings = <Map<String, dynamic>>[];

  for (final m in _tagRe.allMatches(xml)) {
    final tag = m.group(1)!;
    final a = attrs(m.group(2)!);
    final name = a['android:name'] ?? '';
    if (tag.startsWith('uses-permission')) {
      final cat = classify(name);
      if (cat != null) {
        findings.add({
          'category': cat,
          'permission': shortName(name),
          'kind': 'uses-permission',
          'via': '',
          'remove': '<$tag android:name="$name" tools:node="remove"/>',
          'sources': sourcesFor('$tag#$name'),
        });
      }
    } else {
      final perm = shortName(a['android:permission'] ?? '');
      if (perm != null && componentPerms.contains(perm)) {
        findings.add({
          'category': lookup[perm]!,
          'permission': perm,
          'kind': '$tag declaration',
          'via': name,
          'remove': '<$tag android:name="$name" tools:node="remove"/>',
          'sources': sourcesFor('$tag#$name'),
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
          'sources': sourcesFor('service#$name'),
        });
      }
    }
  }

  // Always write the JSON file, even when there are no findings, so CI
  // steps that expect it do not break.
  if (jsonPath != null) {
    File(jsonPath).writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(findings)}\n',
    );
  }

  print('Manifest: ${manifest.path}');
  if (findings.isEmpty) {
    print('[OK] None of the watched permissions are present '
        'in the final manifest ($variant).');
    return 0;
  }

  print('[!] ${findings.length} watched permission(s)/declaration(s) '
      'found in the final manifest ($variant):\n');
  for (final cat in watchlist.keys) {
    final rows = findings.where((f) => f['category'] == cat).toList()
      ..sort((a, b) =>
          (a['permission'] as String).compareTo(b['permission'] as String));
    if (rows.isEmpty) continue;
    print('[$cat]');
    for (final f in rows) {
      final srcList = f['sources'] as List<String>;
      final src = srcList.isEmpty
          ? (sources.isEmpty ? 'unknown (no merger report)' : 'unknown')
          : srcList.join(', ');
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
      'Note: removing a service or permission that a plugin needs disables '
      'that plugin feature.');

  return failOnFound ? 1 : 0;
}

void main(List<String> argv) {
  try {
    exitCode = run(argv);
  } on FileSystemException catch (e) {
    final where = e.path == null ? '' : ' (${e.path})';
    stderr.writeln('perm_audit: ${e.message}$where');
    exitCode = 2;
  } on FormatException catch (e) {
    stderr.writeln('perm_audit: could not read a file: ${e.message}');
    exitCode = 2;
  }
}
