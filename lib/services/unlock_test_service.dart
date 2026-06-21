import 'dart:async';
import 'dart:convert';
import 'dart:io';

class UnlockTestResult {
  final String id;
  final String name;
  final String status;
  final String? region;
  final DateTime? checkedAt;
  final String? detail;

  const UnlockTestResult({
    required this.id,
    required this.name,
    required this.status,
    this.region,
    this.checkedAt,
    this.detail,
  });

  bool get isPending => status == 'Pending';
  bool get isUnlocked => status == 'Yes';
  bool get isBlocked =>
      status == 'No' ||
      status == 'Blocked' ||
      status == 'Unsupported Country/Region' ||
      status.startsWith('No ');
  bool get isFailed => status.startsWith('Failed');

  UnlockTestResult copyWith({
    String? status,
    String? region,
    DateTime? checkedAt,
    String? detail,
    bool clearDetail = false,
  }) {
    return UnlockTestResult(
      id: id,
      name: name,
      status: status ?? this.status,
      region: region ?? this.region,
      checkedAt: checkedAt ?? this.checkedAt,
      detail: clearDetail ? null : detail ?? this.detail,
    );
  }
}

class UnlockTestService {
  static const List<UnlockTestResult> defaultItems = [
    UnlockTestResult(id: 'netflix', name: 'Netflix', status: 'Pending'),
    UnlockTestResult(id: 'disney', name: 'Disney+', status: 'Pending'),
    UnlockTestResult(
      id: 'youtube',
      name: 'YouTube Premium',
      status: 'Pending',
    ),
    UnlockTestResult(id: 'chatgpt-web', name: 'ChatGPT Web', status: 'Pending'),
    UnlockTestResult(id: 'chatgpt-ios', name: 'ChatGPT iOS', status: 'Pending'),
    UnlockTestResult(id: 'gemini', name: 'Gemini', status: 'Pending'),
    UnlockTestResult(id: 'claude', name: 'Claude', status: 'Pending'),
    UnlockTestResult(id: 'prime-video', name: 'Prime Video', status: 'Pending'),
    UnlockTestResult(id: 'spotify', name: 'Spotify', status: 'Pending'),
    UnlockTestResult(id: 'tiktok', name: 'TikTok', status: 'Pending'),
  ];

  static const _userAgent = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/122.0.0.0 Safari/537.36';

  Future<List<UnlockTestResult>> checkAll({
    required int proxyPort,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final client = _UnlockHttpClient(proxyPort: proxyPort, timeout: timeout);
    try {
      return await Future.wait(
        defaultItems.map((item) => _checkById(client, item.id)),
      );
    } finally {
      client.close();
    }
  }

  Future<UnlockTestResult> checkOne({
    required String id,
    required int proxyPort,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final client = _UnlockHttpClient(proxyPort: proxyPort, timeout: timeout);
    try {
      return await _checkById(client, id);
    } finally {
      client.close();
    }
  }

  Future<UnlockTestResult> _checkById(_UnlockHttpClient client, String id) {
    switch (id) {
      case 'netflix':
        return _checkNetflix(client);
      case 'disney':
        return _checkDisneyPlus(client);
      case 'youtube':
        return _checkYoutubePremium(client);
      case 'chatgpt-web':
        return _checkChatGptWeb(client);
      case 'chatgpt-ios':
        return _checkChatGptIos(client);
      case 'gemini':
        return _checkGemini(client);
      case 'claude':
        return _checkClaude(client);
      case 'prime-video':
        return _checkPrimeVideo(client);
      case 'spotify':
        return _checkSpotify(client);
      case 'tiktok':
        return _checkTikTok(client);
      default:
        return Future.value(_checked(id, id, 'Failed', detail: '未知测试项'));
    }
  }

  Future<UnlockTestResult> _checkNetflix(_UnlockHttpClient client) async {
    const id = 'netflix';
    const name = 'Netflix';

    final fast = await client.get(
      Uri.parse(
        'https://api.fast.com/netflix/speedtest/v2'
        '?https=true&token=YXNkZmFzZGxmbnNkYWZoYXNkZmhrYWxm&urlCount=5',
      ),
    );
    if (fast == null) return _checked(id, name, 'Failed');
    if (fast.statusCode == 403) {
      return _checked(id, name, 'No', detail: 'IP 被 Netflix/Fast.com 拒绝');
    }
    final fastJson = _tryJson(fast.body);
    final fastCountry = _readFastComCountry(fastJson);
    if (fastCountry != null) {
      return _checked(id, name, 'Yes', region: fastCountry);
    }

    final originals = await client.get(
      Uri.parse('https://www.netflix.com/title/81280792'),
      followRedirects: false,
    );
    final licensed = await client.get(
      Uri.parse('https://www.netflix.com/title/70143836'),
      followRedirects: false,
    );
    if (originals == null || licensed == null) {
      return _checked(id, name, 'Failed');
    }

    final status1 = originals.statusCode;
    final status2 = licensed.statusCode;
    if (status1 == 404 && status2 == 404) {
      return _checked(id, name, 'Originals Only');
    }
    if (status1 == 403 || status2 == 403) return _checked(id, name, 'No');
    if ([200, 301, 302].contains(status1) ||
        [200, 301, 302].contains(status2)) {
      final regionProbe = await client.get(
        Uri.parse('https://www.netflix.com/title/80018499'),
        followRedirects: false,
      );
      final location = regionProbe?.headers[HttpHeaders.locationHeader];
      final region = _netflixRegionFromLocation(location);
      return _checked(id, name, 'Yes', region: region);
    }
    return _checked(id, name, 'Failed', detail: '状态码 $status1/$status2');
  }

  Future<UnlockTestResult> _checkDisneyPlus(_UnlockHttpClient client) async {
    const id = 'disney';
    const name = 'Disney+';
    const auth =
        'Bearer ZGlzbmV5JmJyb3dzZXImMS4wLjA.Cu56AgSfBTDag5NiRA81oLHkDZfu5L3CKadnefEAY84';

    final device = await client.postJson(
      Uri.parse('https://disney.api.edge.bamgrid.com/devices'),
      headers: {'authorization': auth},
      body: const {
        'deviceFamily': 'browser',
        'applicationRuntime': 'chrome',
        'deviceProfile': 'windows',
        'attributes': <String, Object?>{},
      },
    );
    if (device == null) {
      return _checked(id, name, 'Failed (Network Connection)');
    }
    if (device.statusCode == 403) {
      return _checked(id, name, 'No', detail: 'IP 被 Disney+ 拒绝');
    }

    final assertion = RegExp(r'"assertion"\s*:\s*"([^"]+)"')
        .firstMatch(device.body)
        ?.group(1);
    if (assertion == null || assertion.isEmpty) {
      final mainRegion = await _disneyRegionFromMainPage(client);
      if (mainRegion != null) {
        return _checked(id, name, 'Yes', region: mainRegion);
      }
      return _checked(id, name, 'Failed', detail: '无法获取设备 assertion');
    }

    final token = await client.postForm(
      Uri.parse('https://disney.api.edge.bamgrid.com/token'),
      headers: {'authorization': auth},
      fields: {
        'grant_type': 'urn:ietf:params:oauth:grant-type:token-exchange',
        'latitude': '0',
        'longitude': '0',
        'platform': 'browser',
        'subject_token': assertion,
        'subject_token_type': 'urn:bamtech:params:oauth:token-type:device',
      },
    );
    if (token == null) return _checked(id, name, 'Failed (Network Connection)');
    if (token.body.contains('forbidden-location') ||
        token.body.contains('403 ERROR') ||
        token.statusCode == 403) {
      return _checked(id, name, 'No', detail: 'IP 被 Disney+ 拒绝');
    }

    final refreshToken = (_tryJson(token.body)?['refresh_token'] as String?) ??
        RegExp(r'"refresh_token"\s*:\s*"([^"]+)"')
            .firstMatch(token.body)
            ?.group(1);
    if (refreshToken == null || refreshToken.isEmpty) {
      final mainRegion = await _disneyRegionFromMainPage(client);
      if (mainRegion != null) {
        return _checked(id, name, 'Yes', region: mainRegion);
      }
      return _checked(id, name, 'Failed', detail: '无法获取 refresh token');
    }

    final graph = await client.postJsonText(
      Uri.parse('https://disney.api.edge.bamgrid.com/graph/v1/device/graphql'),
      headers: {'authorization': auth},
      body:
          '{"query":"mutation refreshToken(\\\$input: RefreshTokenInput!) { refreshToken(refreshToken: \\\$input) { activeSession { sessionId } } }","variables":{"input":{"refreshToken":"$refreshToken"}}}',
    );
    if (graph == null) return _checked(id, name, 'Failed (Network Connection)');
    if (graph.body.contains('forbidden-location') || graph.statusCode == 403) {
      return _checked(id, name, 'No', detail: '服务不可用');
    }

    final region = await _disneyRegionFromMainPage(client);
    return _checked(id, name, 'Yes', region: region);
  }

  Future<UnlockTestResult> _checkYoutubePremium(
    _UnlockHttpClient client,
  ) async {
    const id = 'youtube';
    const name = 'YouTube Premium';
    final response = await client.get(
      Uri.parse('https://www.youtube.com/premium?hl=en'),
    );
    if (response == null) return _checked(id, name, 'Failed');

    final body = response.body;
    final lower = body.toLowerCase();
    final region = _firstRegexGroup(body, [
      RegExp(r'''id=["']country-code["'][^>]*>\s*([A-Za-z]{2,3})\s*<'''),
      RegExp(r'''"GL"\s*:\s*"([A-Za-z]{2})"'''),
      RegExp(r'''"countryCode"\s*:\s*"([A-Za-z]{2})"'''),
      RegExp(r'''"country_code"\s*:\s*"([A-Za-z]{2})"'''),
    ]);
    if (lower.contains('youtube premium is not available in your country') ||
        lower.contains('premium is not available in your country') ||
        lower.contains('premium is not available in your region')) {
      return _checked(id, name, 'No', region: region);
    }
    if (response.statusCode >= 200 &&
        response.statusCode < 300 &&
        (lower.contains('youtube premium') ||
            lower.contains('ad-free') ||
            lower.contains('"browseid":"spunlimited"'))) {
      return _checked(id, name, 'Yes', region: region);
    }
    return _checked(id, name, 'Failed', region: region);
  }

  Future<UnlockTestResult> _checkChatGptWeb(_UnlockHttpClient client) async {
    const id = 'chatgpt-web';
    const name = 'ChatGPT Web';
    final region = await _cloudflareTraceRegion(
      client,
      Uri.parse('https://chat.openai.com/cdn-cgi/trace'),
    );
    final response = await client.get(
      Uri.parse('https://api.openai.com/compliance/cookie_requirements'),
    );
    if (response == null) return _checked(id, name, 'Failed', region: region);
    final lower = response.body.toLowerCase();
    if (lower.contains('unsupported_country')) {
      return _checked(id, name, 'Unsupported Country/Region', region: region);
    }
    return _checked(id, name, 'Yes', region: region);
  }

  Future<UnlockTestResult> _checkChatGptIos(_UnlockHttpClient client) async {
    const id = 'chatgpt-ios';
    const name = 'ChatGPT iOS';
    final region = await _cloudflareTraceRegion(
      client,
      Uri.parse('https://chat.openai.com/cdn-cgi/trace'),
    );
    final response =
        await client.get(Uri.parse('https://ios.chat.openai.com/'));
    if (response == null) return _checked(id, name, 'Failed', region: region);
    final lower = response.body.toLowerCase();
    if (lower.contains('you may be connected to a disallowed isp')) {
      return _checked(id, name, 'Disallowed ISP', region: region);
    }
    if (lower.contains('request is not allowed. please try again later.')) {
      return _checked(id, name, 'Yes', region: region);
    }
    if (lower.contains('sorry, you have been blocked')) {
      return _checked(id, name, 'Blocked', region: region);
    }
    return _checked(id, name, 'Failed', region: region);
  }

  Future<UnlockTestResult> _checkGemini(_UnlockHttpClient client) async {
    const id = 'gemini';
    const name = 'Gemini';
    const blocked = {
      'CHN',
      'RUS',
      'BLR',
      'CUB',
      'IRN',
      'PRK',
      'SYR',
      'HKG',
      'MAC'
    };
    final response = await client.get(Uri.parse('https://gemini.google.com'));
    if (response == null) return _checked(id, name, 'Failed');
    const marker = ',2,1,200,"';
    final index = response.body.indexOf(marker);
    final code = index >= 0 && response.body.length >= index + marker.length + 3
        ? response.body
            .substring(index + marker.length, index + marker.length + 3)
        : null;
    if (code == null || !RegExp(r'^[A-Z]{3}$').hasMatch(code)) {
      return _checked(id, name, 'Failed');
    }
    return _checked(id, name, blocked.contains(code) ? 'No' : 'Yes',
        region: code);
  }

  Future<UnlockTestResult> _checkClaude(_UnlockHttpClient client) async {
    const id = 'claude';
    const name = 'Claude';
    const blocked = {
      'AF',
      'BY',
      'CN',
      'CU',
      'HK',
      'IR',
      'KP',
      'MO',
      'RU',
      'SY'
    };
    final region = await _cloudflareTraceRegion(
      client,
      Uri.parse('https://claude.ai/cdn-cgi/trace'),
    );
    if (region == null) return _checked(id, name, 'Failed');
    return _checked(id, name, blocked.contains(region) ? 'No' : 'Yes',
        region: region);
  }

  Future<UnlockTestResult> _checkPrimeVideo(_UnlockHttpClient client) async {
    const id = 'prime-video';
    const name = 'Prime Video';
    final response = await client.get(Uri.parse('https://www.primevideo.com'));
    if (response == null) {
      return _checked(id, name, 'Failed (Network Connection)');
    }
    final body = response.body;
    if (body.contains('isServiceRestricted')) {
      return _checked(id, name, 'No', detail: '服务不可用');
    }
    final region =
        RegExp(r'"currentTerritory":"([^"]+)"').firstMatch(body)?.group(1);
    if (region != null) return _checked(id, name, 'Yes', region: region);
    return _checked(id, name, 'Failed');
  }

  Future<UnlockTestResult> _checkSpotify(_UnlockHttpClient client) async {
    const id = 'spotify';
    const name = 'Spotify';
    final response = await client.get(
      Uri.parse(
        'https://www.spotify.com/api/content/v1/country-selector'
        '?platform=web&format=json',
      ),
    );
    if (response == null) return _checked(id, name, 'Failed');
    if (response.statusCode == 403 || response.statusCode == 451) {
      return _checked(id, name, 'No');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return _checked(id, name, 'Failed', detail: '状态码 ${response.statusCode}');
    }
    final lower = response.body.toLowerCase();
    if (lower.contains('not available in your country')) {
      return _checked(id, name, 'No');
    }
    final region = RegExp(r'"countryCode"\s*:\s*"([^"]+)"')
        .firstMatch(response.body)
        ?.group(1);
    return _checked(id, name, 'Yes', region: region);
  }

  Future<UnlockTestResult> _checkTikTok(_UnlockHttpClient client) async {
    const id = 'tiktok';
    const name = 'TikTok';
    final trace = await client.get(
      Uri.parse('https://www.tiktok.com/cdn-cgi/trace'),
    );
    if (trace != null) {
      final status = _tikTokStatus(trace.statusCode, trace.body);
      final region = _traceValue(trace.body, 'loc') ??
          RegExp(r'"region"\s*:\s*"([a-zA-Z-]+)"')
              .firstMatch(trace.body)
              ?.group(1)
              ?.split('-')
              .first;
      if (status != 'Failed' || region != null) {
        return _checked(id, name, status, region: region);
      }
    }

    final home = await client.get(Uri.parse('https://www.tiktok.com/'));
    if (home == null) return _checked(id, name, 'Failed');
    final region = RegExp(r'"region"\s*:\s*"([a-zA-Z-]+)"')
        .firstMatch(home.body)
        ?.group(1)
        ?.split('-')
        .first;
    return _checked(id, name, _tikTokStatus(home.statusCode, home.body),
        region: region);
  }

  Future<String?> _cloudflareTraceRegion(
    _UnlockHttpClient client,
    Uri uri,
  ) async {
    final response = await client.get(uri);
    if (response == null) return null;
    return _traceValue(response.body, 'loc');
  }

  Future<String?> _disneyRegionFromMainPage(_UnlockHttpClient client) async {
    final response = await client.get(Uri.parse('https://www.disneyplus.com/'));
    if (response == null) return null;
    return RegExp(r'"region"\s*:\s*"([^"]+)"')
        .firstMatch(response.body)
        ?.group(1)
        ?.toUpperCase();
  }

  String _tikTokStatus(int statusCode, String body) {
    if (statusCode == 403 || statusCode == 451) return 'No';
    if (statusCode < 200 || statusCode >= 300) return 'Failed';
    final lower = body.toLowerCase();
    if (lower.contains('access denied') ||
        lower.contains('not available in your region') ||
        lower.contains('tiktok is not available')) {
      return 'No';
    }
    return 'Yes';
  }

  UnlockTestResult _checked(
    String id,
    String name,
    String status, {
    String? region,
    String? detail,
  }) {
    return UnlockTestResult(
      id: id,
      name: name,
      status: status,
      region: _normalizeRegion(region),
      detail: detail,
      checkedAt: DateTime.now(),
    );
  }

  String? _normalizeRegion(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed.toUpperCase();
  }

  Map<String, dynamic>? _tryJson(String body) {
    try {
      final parsed = jsonDecode(body);
      return parsed is Map<String, dynamic> ? parsed : null;
    } catch (_) {
      return null;
    }
  }

  String? _readFastComCountry(Map<String, dynamic>? data) {
    final targets = data?['targets'];
    if (targets is! List || targets.isEmpty) return null;
    final first = targets.first;
    if (first is! Map) return null;
    final location = first['location'];
    if (location is! Map) return null;
    return location['country']?.toString();
  }

  String? _netflixRegionFromLocation(String? location) {
    if (location == null || location.isEmpty) return null;
    final segments = Uri.tryParse(location)?.pathSegments;
    if (segments == null || segments.isEmpty) return null;
    final maybeCode = segments.first.split('-').first.toUpperCase();
    if (RegExp(r'^[A-Z]{2,3}$').hasMatch(maybeCode)) return maybeCode;
    return null;
  }

  String? _firstRegexGroup(String body, List<RegExp> expressions) {
    for (final expression in expressions) {
      final match = expression.firstMatch(body);
      final value = match?.group(1);
      if (value != null && value.isNotEmpty) return value.toUpperCase();
    }
    return null;
  }

  String? _traceValue(String body, String key) {
    for (final line in body.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.startsWith('$key=')) {
        final value = trimmed.substring(key.length + 1).trim();
        if (value.isNotEmpty) return value.toUpperCase();
      }
    }
    return null;
  }
}

class _UnlockHttpClient {
  final int proxyPort;
  final Duration timeout;
  late final HttpClient _client;

  _UnlockHttpClient({
    required this.proxyPort,
    required this.timeout,
  }) {
    _client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8)
      ..idleTimeout = const Duration(seconds: 10)
      ..findProxy = ((_) => 'PROXY 127.0.0.1:$proxyPort')
      ..badCertificateCallback = ((_, __, ___) => true);
  }

  Future<_UnlockResponse?> get(
    Uri uri, {
    Map<String, String>? headers,
    bool followRedirects = true,
  }) async {
    return _request(
      'GET',
      uri,
      headers: headers,
      followRedirects: followRedirects,
    );
  }

  Future<_UnlockResponse?> postJson(
    Uri uri, {
    Map<String, String>? headers,
    required Map<String, Object?> body,
  }) {
    return postJsonText(uri, headers: headers, body: jsonEncode(body));
  }

  Future<_UnlockResponse?> postJsonText(
    Uri uri, {
    Map<String, String>? headers,
    required String body,
  }) {
    return _request(
      'POST',
      uri,
      headers: {
        ...?headers,
        HttpHeaders.contentTypeHeader: 'application/json; charset=UTF-8',
      },
      body: utf8.encode(body),
    );
  }

  Future<_UnlockResponse?> postForm(
    Uri uri, {
    Map<String, String>? headers,
    required Map<String, String> fields,
  }) {
    return _request(
      'POST',
      uri,
      headers: {
        ...?headers,
        HttpHeaders.contentTypeHeader: 'application/x-www-form-urlencoded',
      },
      body: utf8.encode(
        fields.entries
            .map(
              (entry) =>
                  '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(entry.value)}',
            )
            .join('&'),
      ),
    );
  }

  Future<_UnlockResponse?> _request(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    bool followRedirects = true,
    List<int>? body,
  }) async {
    try {
      final request = await _client.openUrl(method, uri).timeout(timeout);
      request.followRedirects = followRedirects;
      request.headers
          .set(HttpHeaders.userAgentHeader, UnlockTestService._userAgent);
      request.headers.set(HttpHeaders.acceptHeader, '*/*');
      for (final entry in (headers ?? const <String, String>{}).entries) {
        request.headers.set(entry.key, entry.value);
      }
      if (body != null) {
        request.contentLength = body.length;
        request.add(body);
      }
      final response = await request.close().timeout(timeout);
      final text = await response
          .transform(const Utf8Decoder(allowMalformed: true))
          .join()
          .timeout(timeout);
      final headerMap = <String, String>{};
      response.headers.forEach((name, values) {
        if (values.isNotEmpty) headerMap[name.toLowerCase()] = values.first;
      });
      return _UnlockResponse(
        statusCode: response.statusCode,
        body: text,
        headers: headerMap,
      );
    } catch (_) {
      return null;
    }
  }

  void close() {
    _client.close(force: true);
  }
}

class _UnlockResponse {
  final int statusCode;
  final String body;
  final Map<String, String> headers;

  const _UnlockResponse({
    required this.statusCode,
    required this.body,
    required this.headers,
  });
}
