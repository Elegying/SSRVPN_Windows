import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ssrvpn_windows/models/app_settings.dart';
import 'package:ssrvpn_windows/services/clash_service.dart';
import 'package:ssrvpn_windows/services/subscription_service.dart';
import 'package:yaml/yaml.dart';

void main() {
  late Directory tempDir;
  late SubscriptionService service;

  setUp(() async {
    SubscriptionService.resetInstanceForTesting();
    tempDir = await Directory.systemTemp.createTemp('ssrvpn-windows-test-');
    service = await SubscriptionService.getInstance(tempDir.path);
  });

  tearDown(() async {
    SubscriptionService.resetInstanceForTesting();
    await tempDir.delete(recursive: true);
  });

  test('imports the valid SSR link and preserves its remark', () {
    const link =
        'ssr://MTAzLjIzMi4yMTMuOTQ6MTg4OTk6YXV0aF9hZXMxMjhfbWQ1OmFlcy0yNTYtY2ZiOnRsczEuMl90aWNrZXRfYXV0aDpibWxyZFdGcGJXOWlhUS8_cmVtYXJrcz01NmVCNWE2MjZMMm1MVEl3TWpVJnByb3RvcGFyYW09TVRBNE1UcDVhWGRoYVhSNWIzVSZvYmZzcGFyYW09ZDNkM0xtSmhhV1IxTG1OdmJR';

    final yaml = service.importSsrLink(link);
    expect(yaml, isNotNull);

    final proxy = (loadYaml(yaml!)['proxies'] as YamlList).single as YamlMap;
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

  test('local node changes persist and can be parsed again', () async {
    await service.setRawYaml(_editableYaml);
    await service.updateNode('Alpha', {
      'name': 'Alpha Local',
      'type': 'vmess',
      'server': 'local.example.com',
      'port': 8443,
      'uuid': 'updated-uuid',
      'alterId': 0,
      'network': 'ws',
      'tls': true,
      'ws-opts': {
        'path': '/preserved',
        'headers': {'Host': 'cdn.example.com'},
      },
    });

    final cache = File('${tempDir.path}/subscription_cache.yaml');
    final parsed = loadYaml(await cache.readAsString()) as YamlMap;
    expect(parsed['proxies'][0]['name'], 'Alpha Local');
    expect(parsed['proxies'][0]['server'], 'local.example.com');
    expect(parsed['proxies'][0]['tls'], isTrue);
    expect(parsed['proxies'][0]['ws-opts']['path'], '/preserved');
    final clashConfig = ClashService().generateClashConfig(
      service.rawYaml!,
      AppSettings(),
      preferredNodeName: 'Alpha Local',
    );
    expect(
      (loadYaml(clashConfig) as YamlMap)['proxies'][0]['name'],
      'Alpha Local',
    );

    SubscriptionService.resetInstanceForTesting();
    service = await SubscriptionService.getInstance(tempDir.path);
    expect(service.allNodes.single.name, 'Alpha Local');
    expect(service.allNodes.single.extra['uuid'], 'updated-uuid');
  });

  test('renaming a node updates proxy group references', () async {
    await service.setRawYaml(_editableYaml);
    final updated = Map<String, dynamic>.from(service.allNodes.single.extra)
      ..['name'] = 'Renamed';

    await service.updateNode('Alpha', updated);

    final parsed = loadYaml(service.rawYaml!) as YamlMap;
    expect(parsed['proxy-groups'][0]['proxies'], ['Renamed', 'DIRECT']);
  });

  test('duplicate node names are rejected', () async {
    await service.setRawYaml('''
proxies:
  - name: Alpha
    type: ss
    server: alpha.example.com
    port: 1001
  - name: Beta
    type: ss
    server: beta.example.com
    port: 1002
''');
    final updated = Map<String, dynamic>.from(service.allNodes.first.extra)
      ..['name'] = 'Beta';

    await expectLater(
      service.updateNode('Alpha', updated),
      throwsA(
        isA<Exception>().having(
          (error) => error.toString(),
          'message',
          contains('已存在'),
        ),
      ),
    );
    expect(service.allNodes.first.name, 'Alpha');
  });

  test('subscription refresh replaces local node changes', () async {
    const remoteYaml = '''
proxies:
  - name: Remote
    type: ss
    server: remote.example.com
    port: 8388
    cipher: aes-128-gcm
    password: remote-password
''';
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) {
      request.response
        ..headers.contentType = ContentType.text
        ..write(remoteYaml)
        ..close();
    });

    await service.addSubscription(
      'Remote feed',
      'http://${server.address.address}:${server.port}/subscription',
    );
    await service.refreshAllSubscriptions();
    final local = Map<String, dynamic>.from(service.allNodes.single.extra)
      ..['server'] = 'local.example.com'
      ..['password'] = 'local-password';
    await service.updateNode('Remote', local);
    expect(service.allNodes.single.server, 'local.example.com');

    await service.refreshAllSubscriptions();
    expect(service.allNodes.single.server, 'remote.example.com');
    expect(service.allNodes.single.extra['password'], 'remote-password');
  });
}

const _editableYaml = '''
proxies:
  - name: Alpha
    type: vmess
    server: alpha.example.com
    port: 443
    uuid: original-uuid
    alterId: 0
    network: ws
    tls: true
    ws-opts:
      path: /preserved
      headers:
        Host: cdn.example.com
proxy-groups:
  - name: Example
    type: select
    proxies:
      - Alpha
      - DIRECT
''';
