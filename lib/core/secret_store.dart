import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Where credentials are kept: the system's own store for secrets — the
/// Keychain on macOS, Credential Manager on Windows, the Secret Service on
/// Linux — rather than a preferences file anything running as the same user
/// can read.
///
/// An interface so tests can stand in for the system, and so a store that
/// cannot be reached can be told apart from one that holds nothing: every
/// method throws when the store is not there, and [read] answers null only
/// for a key it does not have.
abstract class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);

  /// The one the app uses. Replaced in tests.
  static SecretStore instance = SystemSecretStore();
}

class SystemSecretStore implements SecretStore {
  SystemSecretStore()
      : _storage = FlutterSecureStorage(
          // The data protection keychain wants a keychain-access-groups
          // entitlement, and that wants a provisioning profile — which an
          // ad-hoc signed build does not have. The login keychain needs
          // neither, and nothing here is shared with another app.
          mOptions: Platform.isMacOS
              ? const MacOsOptions(
                  accountName: 'Codora',
                  usesDataProtectionKeychain: false,
                )
              : MacOsOptions.defaultOptions,
        );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}
