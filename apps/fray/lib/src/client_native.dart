import 'dart:io';

import 'package:http/http.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'session_cookies.dart';

Client createClient() => SessionClient();

class SessionClient extends BaseClient {
  final HttpClient _client = HttpClient();
  static const _storage = FlutterSecureStorage();
  final SessionCookies _cookies = SessionCookies(
    read: (key) => _storage.read(key: key),
    write: (key, value) => _storage.write(key: key, value: value),
  );

  @override
  Future<StreamedResponse> send(BaseRequest request) async {
    final outgoing = await _client.openUrl(request.method, request.url);
    outgoing.followRedirects = false;
    request.headers.forEach(outgoing.headers.set);
    outgoing.headers.set('Origin', request.url.origin);
    outgoing.cookies.addAll(await _cookies.forRequest(request.url));
    await outgoing.addStream(request.finalize());
    final response = await outgoing.close();
    if (response.cookies.isNotEmpty) {
      await _cookies.receive(request.url, response.cookies);
    }
    final headers = <String, String>{};
    response.headers.forEach(
      (name, values) => headers[name] = values.join(','),
    );
    return StreamedResponse(
      response,
      response.statusCode,
      headers: headers,
      request: request,
    );
  }

  @override
  void close() {
    _client.close(force: true);
    super.close();
  }
}
