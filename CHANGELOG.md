## 0.1.1

- Fix: report sources on Windows (backslash paths) are now parsed correctly.
- Fix: only platform permissions (`android.permission.*`) match; a custom
  permission like `com.example.permission.READ_CONTACTS` is no longer flagged.
- Fix: `--json` always writes the file, even when nothing is found.
- Fix: no crash when an option is missing its value; `--opt=value` supported.
- Fix: output is no longer lost when piped (no `exit()` before flush).
- Fix: variant lookup is an exact match and lists available variants on error.
- Fix: attributes with `>` or single quotes in the manifest are parsed.
- Add: `--help`, exit-code documentation, stale-build warning.
- Change: output uses plain ASCII markers (`[!]`, `[OK]`) instead of emoji.

## 0.1.0

- Initial release: lists sensitive Android permissions and services in the
  final merged manifest, shows which dependency added each one, and prints the
  exact `tools:node="remove"` line to strip it.