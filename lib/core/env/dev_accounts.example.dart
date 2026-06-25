/// Dev account roster — TEMPLATE.
///
/// Copy this file to `dev_accounts.dart` (which is gitignored) and fill in
/// real test-account credentials. Used ONLY by [DevAccountSwitcher], which is
/// itself gated by `kDebugMode` — this data never ships in a release build.
///
///   cp lib/core/env/dev_accounts.example.dart lib/core/env/dev_accounts.dart
library;

import 'package:flutter/foundation.dart';

class DevAccount {
  const DevAccount(this.label, this.email, this.password);
  final String label;
  final String email;
  final String password;
}

/// Empty outside debug builds, so the switcher renders nothing and these
/// strings never reach a release binary's constant pool.
List<DevAccount> get kDevAccounts => kDebugMode
    ? const [
        DevAccount('Name', 'name@example.com', 'password'),
      ]
    : const [];
