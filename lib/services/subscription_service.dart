import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:yaml/yaml.dart';
import 'package:uuid/uuid.dart';
import '../models/subscription.dart';
import '../models/proxy_node.dart';
import '../models/proxy_group.dart';

/// 订阅管理服务
class SubscriptionService {
  static SubscriptionService? _instance;
  final Uuid _uuid = const Uuid();

  List<Subscription> _subscriptions = [];
  String? _rawYaml; // 合并后的原始YAML配置
  String? _cacheDir;

  List<ProxyNode> _allNodes = [];
  List<ProxyGroup> _allGroups = [];

  SubscriptionService._();

  static Future<SubscriptionService> getInstance(String cacheDir) async {
    if (_instance == null) {
      _instance = SubscriptionService._();
      _instance!._cacheDir = cacheDir;
      await _instance!._loadFromDisk();
    }
    return _instance!;
  }

  List<Subscription> get subscriptions => List.unmodifiable(_subscriptions);
  String? get rawYaml => _rawYaml;
  List<ProxyNode> get allNodes => List.unmodifiable(_allNodes);
  List<ProxyGroup> get allGroups => List.unmodifiable(_allGroups);

  /// 添加订阅
  Future<Subscription> addSubscription(String name, String url) async {
    final sub = Subscription(
      id: _uuid.v4(),
      name: name,
      url: url,
    );
    _subscriptions.add(sub);
    await _saveToDisk();
    return sub;
  }

  /// 删除订阅
  Future<void> removeSubscription(String id) async {
    _subscriptions.removeWhere((s) => s.id == id);
    await _saveToDisk();

    if (_subscriptions.isEmpty) {
      _rawYaml = null;
      _allNodes = [];
      _allGroups = [];
      try {
        final cacheFile = File('$_cacheDir/subscription_cache.yaml');
        if (await cacheFile.exists()) await cacheFile.delete();
      } catch (_) {}
    }
  }

  /// 更新订阅
  Future<void> updateSubscription(Subscription updated) async {
    final index = _subscriptions.indexWhere((s) => s.id == updated.id);
    if (index >= 0) {
      _subscriptions[index] = updated;
      await _saveToDisk();
    }
  }

  /// 从URL拉取订阅配置
  Future<String?> fetchSubscription(String url) async {
    try {
      final uri = Uri.parse(url);
      final response = await http.get(
        uri,
        headers: {
          'User-Agent': 'clash-verge/v2.0.0',
          'Accept': 'text/yaml, application/x-yaml, */*',
        },
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        String body = response.body;

        // 尝试 Base64 解码（许多订阅使用 Base64 编码）
        if (_isLikelyBase64(body)) {
          try {
            body = utf8.decode(base64Decode(body.trim()));
          } catch (_) {
            // 保持原始内容
          }
        }

        return body;
      } else {
        throw Exception('HTTP ${response.statusCode}: 订阅获取失败');
      }
    } catch (e) {
      throw Exception('获取订阅失败: $e');
    }
  }

  /// 刷新所有订阅
  Future<String?> refreshAllSubscriptions() async {
    if (_subscriptions.isEmpty) {
      _rawYaml = null;
      _allNodes = [];
      _allGroups = [];
      return null;
    }

    final allYamlBuffers = <String>[];
    bool hasData = false;

    for (final sub in _subscriptions.where((s) => s.enabled)) {
      try {
        String? yaml;
        if (isSsrLink(sub.url)) {
          yaml = importSsrLink(sub.url);
        } else {
          yaml = await fetchSubscription(sub.url);
        }
        if (yaml != null && yaml.isNotEmpty) {
          allYamlBuffers.add(yaml);
          hasData = true;
        }
      } catch (e) {
        continue;
      }
    }

    if (!hasData) return null;

    // 合并多个订阅的YAML
    _rawYaml = _mergeYamlConfigs(allYamlBuffers);

    // 缓存到磁盘
    if (_rawYaml != null) {
      await _cacheYaml(_rawYaml!);
    }

    // 解析节点和组
    _parseYaml();

    // 更新最后更新时间
    final now = DateTime.now();
    for (final sub in _subscriptions) {
      sub.lastUpdate = now;
    }
    await _saveToDisk();

    return _rawYaml;
  }

  /// 合并多个YAML配置
  /// 从YAML文本中提取指定顶层段的原始内容
  String _extractSection(String yaml, String sectionName) {
    final lines = yaml.split('\n');
    final sectionLines = <String>[];
    bool inSection = false;

    for (final line in lines) {
      // 顶层段检测：不以空格/tab开头
      if (!line.startsWith(' ') && !line.startsWith('\t')) {
        if (line.trim().startsWith('$sectionName:')) {
          inSection = true;
          continue;
        } else if (inSection && line.trim().contains(':') && !line.trim().startsWith('#') && !line.trim().startsWith('-')) {
          // 遇到下一个顶层段，停止
          break;
        }
      }
      if (inSection) {
        sectionLines.add(line);
      }
    }

    // 计算最小缩进（排除空行）
    int minIndent = 999;
    for (final line in sectionLines) {
      final t = line.trimLeft();
      if (t.isEmpty) continue;
      final indent = line.length - t.length;
      if (indent < minIndent) minIndent = indent;
    }
    if (minIndent == 999) minIndent = 0;

    // 重建：保留相对缩进，归一化基准为2空格
    final buffer = StringBuffer();
    for (final line in sectionLines) {
      final trimmed = line.trimLeft();
      if (trimmed.isEmpty) continue;
      final delta = line.length - trimmed.length - minIndent;
      buffer.writeln('${' ' * (delta + 2)}$trimmed');
    }
    return buffer.toString().trimRight();
  }

  /// 合并多个YAML配置（只合并proxies节点，规则和分流不取自订阅）
  String _mergeYamlConfigs(List<String> yamls) {
    if (yamls.isEmpty) return '';

    final allProxies = <String>[];

    for (final yaml in yamls) {
      final proxiesText = _extractSection(yaml, 'proxies');
      if (proxiesText.isNotEmpty) {
        allProxies.add(proxiesText);
      }
    }

    if (allProxies.isEmpty) return '';

    final buffer = StringBuffer();
    buffer.writeln('proxies:');
    for (final p in allProxies) {
      buffer.writeln(p);
    }

    return buffer.toString();
  }

  /// 解析YAML获取节点和组
  void _parseYaml() {
    if (_rawYaml == null) return;

    try {
      final doc = loadYaml(_rawYaml!);
      if (doc is! Map) return;

      _allNodes = [];
      _allGroups = [];

      // 解析代理节点
      final proxies = doc['proxies'];
      if (proxies is List) {
        for (final proxy in proxies) {
          if (proxy is Map) {
            final name = proxy['name'] as String? ?? 'Unknown';
            _allNodes.add(ProxyNode(
              name: name,
              type: proxy['type'] as String? ?? 'ss',
              server: proxy['server'] as String? ?? '',
              port: proxy['port'] as int? ?? 0,
              group: '全部节点',
              extra: Map<String, dynamic>.from(proxy as Map),
            ));
          }
        }
      }

      // 解析代理组
      final proxyGroups = doc['proxy-groups'];
      if (proxyGroups is List) {
        for (final group in proxyGroups) {
          if (group is Map) {
            final groupName = group['name'] as String? ?? 'Unknown';
            final groupType = group['type'] as String? ?? 'select';
            final groupProxies = (group['proxies'] as List?)
                    ?.map((e) => e.toString())
                    .toList() ??
                [];

            // 查找组中的节点
            final groupNodes = <ProxyNode>[];
            for (final proxyName in groupProxies) {
              // 在allNodes中查找
              final node = _allNodes.firstWhere(
                (n) => n.name == proxyName,
                orElse: () => ProxyNode(
                  name: proxyName,
                  type: 'unknown',
                  server: '',
                  port: 0,
                  group: groupName,
                ),
              );
              if (node.name != 'unknown' || proxyName == 'DIRECT' || proxyName == 'REJECT') {
                groupNodes.add(node);
              }
            }

            _allGroups.add(ProxyGroup(
              name: groupName,
              type: groupType,
              nodes: groupNodes,
            ));
          }
        }
      }
    } catch (e) {
      // YAML解析失败
    }
  }

  /// 判断是否为SSR链接
  bool isSsrLink(String input) {
    return input.trim().toLowerCase().startsWith('ssr://');
  }

  /// 导入SSR链接，返回生成的YAML配置片段
  String? importSsrLink(String ssrLink) {
    try {
      final link = ssrLink.trim();
      if (!link.toLowerCase().startsWith('ssr://')) return null;

      // 去掉 ssr:// 前缀
      final encoded = link.substring(6);
      // Base64 解码
      final decoded = utf8.decode(base64Decode(_fixBase64(encoded)));

      // SSR格式: server:port:protocol:method:obfs:base64password/?params
      final mainPart = decoded.split('/?').first;
      final params = decoded.contains('/?') ? decoded.split('/?').last : '';

      final parts = mainPart.split(':');
      if (parts.length < 6) return null;

      final server = parts[0];
      final port = int.tryParse(parts[1]) ?? 0;
      final protocol = parts[2];
      final method = parts[3];
      final obfs = parts[4];
      // password 是 base64 编码的
      final passwordB64 = parts.sublist(5).join(':');
      final password = utf8.decode(base64Decode(_fixBase64(passwordB64)));

      // 解析参数
      final paramMap = <String, String>{};
      if (params.isNotEmpty) {
        for (final param in params.split('&')) {
          final kv = param.split('=');
          if (kv.length == 2) {
            paramMap[kv[0]] = kv[1];
          }
        }
      }

      final remarks = paramMap['remarks'] != null
          ? utf8.decode(base64Decode(_fixBase64(paramMap['remarks']!)))
          : '$server:$port';

      final obfsparam = paramMap['obfsparam'] != null
          ? utf8.decode(base64Decode(_fixBase64(paramMap['obfsparam']!)))
          : '';
      final protoparam = paramMap['protoparam'] != null
          ? utf8.decode(base64Decode(_fixBase64(paramMap['protoparam']!)))
          : '';

      // 生成 Clash 格式的 YAML
      final buffer = StringBuffer();
      buffer.writeln('proxies:');
      buffer.writeln('  - name: $remarks');
      buffer.writeln('    type: ssr');
      buffer.writeln('    server: $server');
      buffer.writeln('    port: $port');
      buffer.writeln('    cipher: $method');
      buffer.writeln('    password: $password');
      buffer.writeln('    protocol: $protocol');
      if (protoparam.isNotEmpty) {
        buffer.writeln('    protocol-param: "$protoparam"');
      }
      buffer.writeln('    obfs: $obfs');
      if (obfsparam.isNotEmpty) {
        buffer.writeln('    obfs-param: "$obfsparam"');
      }
      buffer.writeln('    udp: true');

      return buffer.toString();
    } catch (e) {
      return null;
    }
  }

  /// 修复Base64 padding
  String _fixBase64(String str) {
    var s = str.replaceAll('-', '+').replaceAll('_', '/');
    final mod = s.length % 4;
    if (mod == 2) s += '==';
    if (mod == 3) s += '=';
    return s;
  }

  /// 判断是否为Base64编码
  bool _isLikelyBase64(String str) {
    final trimmed = str.trim();
    if (trimmed.length % 4 != 0) return false;
    final base64Pattern = RegExp(r'^[A-Za-z0-9+/]*={0,2}$');
    return base64Pattern.hasMatch(trimmed) && trimmed.length > 20;
  }

  /// 缓存YAML到磁盘
  Future<void> _cacheYaml(String yaml) async {
    if (_cacheDir == null) return;
    final file = File('$_cacheDir/subscription_cache.yaml');
    await file.writeAsString(yaml);
  }

  /// 设置原始YAML并重新解析（用于SSR导入等场景）
  void setRawYaml(String yaml) {
    _rawYaml = yaml;
    _parseYaml();
    _cacheYaml(yaml);
  }

  /// 从磁盘加载缓存
  Future<void> _loadFromDisk() async {
    if (_cacheDir == null) return;

    // 加载订阅列表
    final subsFile = File('$_cacheDir/subscriptions.json');
    if (await subsFile.exists()) {
      try {
        final content = await subsFile.readAsString();
        final list = jsonDecode(content) as List;
        _subscriptions = list
            .map((e) => Subscription.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (e) {
        _subscriptions = [];
      }
    }

    // 加载缓存的YAML
    final cacheFile = File('$_cacheDir/subscription_cache.yaml');
    if (await cacheFile.exists()) {
      _rawYaml = await cacheFile.readAsString();
      _parseYaml();
    }
  }

  /// 保存订阅列表到磁盘
  Future<void> _saveToDisk() async {
    if (_cacheDir == null) return;
    final file = File('$_cacheDir/subscriptions.json');
    final jsonStr = jsonEncode(_subscriptions.map((s) => s.toJson()).toList());
    await file.writeAsString(jsonStr);
  }
}
