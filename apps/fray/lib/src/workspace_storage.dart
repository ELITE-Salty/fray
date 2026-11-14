import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'app_config.dart';

abstract interface class WorkspaceStorage {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> clear();
}

/// Separate from login cookies; logout/account deletion removes the workspace.
class SecureWorkspaceStorage implements WorkspaceStorage {
  static const storage = FlutterSecureStorage();
  String get key =>
      'fray.workspace.v1.${base64Url.encode(utf8.encode(apiUri('/').origin))}';
  @override
  Future<String?> read() => storage.read(key: key);
  @override
  Future<void> write(String value) => storage.write(key: key, value: value);
  @override
  Future<void> clear() => storage.delete(key: key);
}
