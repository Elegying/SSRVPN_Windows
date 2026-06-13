import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

import 'package:ssrvpn_windows/models/app_settings.dart';
import 'package:ssrvpn_windows/models/proxy_node.dart';
import 'package:ssrvpn_windows/services/clash_service.dart';

void main() {
  group('AppSettings', () {
    test('rejects invalid ports and timeouts from persisted JSON', () {
      final settings = AppSettings.fromJson({
        'proxyPort': 70000,
        'socksPort': '1080',
        'apiPort': -1,
        'latencyTestTimeout': 50,
      });

      expect(settings.proxyPort, 7890);
      expect(settings.socksPort, 1080);
      expect(settings.apiPort, 9090);
      expect(settings.latencyTestTimeout, 5000);
      expect(settings.lastSelectedNodeName, isNull);
    });
  });

  group('ClashService configuration', () {
    test('uses selected mode and produces valid YAML', () {
      final settings = AppSettings(
        proxyMode: ProxyMode.global,
        apiSecret: "secret'quoted",
        latencyTestUrl: 'https://example.com/generate_204',
      );
      final config = ClashService().generateClashConfig(
        '''
proxies:
  - name: "Node One"
    type: ss
    server: 127.0.0.1
    port: 8388
    cipher: aes-128-gcm
    password: test
''',
        settings,
      );

      final parsed = loadYaml(config) as YamlMap;
      expect(parsed['mode'], 'global');
      expect(parsed['secret'], "secret'quoted");
      expect(
          parsed['proxy-groups'][1]['url'], 'https://example.com/generate_204');
      expect(parsed['proxies'], hasLength(1));
    });

    test('puts the remembered node first in the PROXY group', () {
      final config = ClashService().generateClashConfig(
        '''
proxies:
  - name: First
    type: ss
    server: 127.0.0.1
    port: 1001
    cipher: aes-128-gcm
    password: test
  - name: Second
    type: ss
    server: 127.0.0.1
    port: 1002
    cipher: aes-128-gcm
    password: test
''',
        AppSettings(lastSelectedNodeName: 'Second'),
        preferredNodeName: 'Second',
      );

      final parsed = loadYaml(config) as YamlMap;
      expect(parsed['proxy-groups'][0]['proxies'], ['Second', 'First']);
      expect(parsed['proxy-groups'][1]['proxies'], ['First', 'Second']);
    });
  });

  test('ProxyNode accepts numeric ports persisted as strings', () {
    final node = ProxyNode.fromJson({
      'name': 'test',
      'server': '127.0.0.1',
      'port': '443',
    });
    expect(node.port, 443);
  });
}
