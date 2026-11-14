import 'package:flutter/foundation.dart';

const apiBase = String.fromEnvironment(
  'FRAY_API_URL',
  defaultValue: kIsWeb ? '' : 'https://frayapi.klanija.com',
);

Uri apiUri(String path) {
  if (apiBase.isEmpty && kIsWeb) return Uri.base.resolve(path);
  final base = Uri.tryParse(apiBase);
  if (base == null ||
      !base.hasAuthority ||
      !['https', 'http'].contains(base.scheme) ||
      base.userInfo.isNotEmpty ||
      base.hasQuery ||
      base.hasFragment ||
      !['', '/'].contains(base.path)) {
    throw const FormatException(
      'FRAY_API_URL must be an API origin such as https://frayapi.klanija.com.',
    );
  }
  if (kReleaseMode && base.scheme != 'https') {
    throw const FormatException('Release builds require an HTTPS API.');
  }
  return base.resolve(path);
}
