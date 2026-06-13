import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ssrvpn_windows/services/subscription_service.dart';
import 'package:yaml/yaml.dart';

void main() {
  late Directory tempDir;
  late SubscriptionService service;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('ssrvpn-windows-test-');
    service = await SubscriptionService.getInstance(tempDir.path);
  });

  tearDownAll(() async {
    await tempDir.delete(recursive: true);
  });

  test('imports the valid SSR link and preserves its remark', () {
    const link =
        'ssr://MTAzLjIzMi4yMTMuOTQ6MTg4OTk6YXV0aF9hZXMxMjhfbWQ1OmFlcy0yNTYtY2ZiOnRsczEuMl90aWNrZXRfYXV0aDpibWxyZFdGcGJXOWlhUS8_cmVtYXJrcz01NmVCNWE2MjZMMm1MVEl3TWpVJnByb3RvcGFyYW09TVRBNE1UcDVhWGRoYVhSNWIzVSZvYmZzcGFyYW09ZDNkM0xtSmhhV1IxTG1OdmJR';

    final yaml = service.importSsrLink(link);
    expect(yaml, isNotNull);

    final proxy = (loadYaml(yaml!)['proxies'] as YamlList).single as YamlMap;
    expect(proxy['name'], '私家车-2025');
    expect(proxy['server'], '103.232.213.94');
    expect(proxy['port'], 18899);
  });

  test('keeps different same-name nodes and removes exact duplicates',
      () async {
    const firstYaml = '''
proxies:
  - name: Shared
    type: ss
    server: first.example.com
    port: 1001
    cipher: aes-128-gcm
    password: first
  - name: Exact
    type: ss
    server: exact.example.com
    port: 1002
    cipher: aes-128-gcm
    password: exact
''';
    const secondYaml = '''
proxies:
  - name: Shared
    type: ss
    server: second.example.com
    port: 2001
    cipher: aes-128-gcm
    password: second
  - name: Exact
    type: ss
    server: exact.example.com
    port: 1002
    cipher: aes-128-gcm
    password: exact
''';

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) {
      request.response
        ..headers.contentType = ContentType.text
        ..write(request.uri.path == '/first' ? firstYaml : secondYaml)
        ..close();
    });

    final origin = 'http://${server.address.address}:${server.port}';
    await service.addSubscription('First feed', '$origin/first');
    await service.addSubscription('Second feed', '$origin/second');
    await service.refreshAllSubscriptions();

    expect(service.allNodes, hasLength(3));
    expect(
      service.allNodes.map((node) => node.name),
      containsAll(['Shared', 'Shared (2)', 'Exact']),
    );
  });
}
