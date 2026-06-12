import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:yaml/yaml.dart';
import '../models/proxy_node.dart';
import '../models/proxy_group.dart';
import '../models/app_settings.dart';

/// Clash Meta 核心管理服务
class ClashService {
  Process? _clashProcess;
  Timer? _statusTimer;
  bool _isRunning = false;
  final String _coreName = 'AtlasCore_amd64.exe';

  AppSettings _settings = AppSettings();
  String _corePath = '';
  String _configDir = '';
  String _configPath = '';

  // 回调
  VoidCallback? onStatusChanged;
  void Function(String message)? onLog;

  bool get isRunning => _isRunning;

  /// 初始化服务，设置路径
  Future<void> init(AppSettings settings) async {
    _settings = settings;

    // 便携模式：所有数据保存在软件根目录的 data/ 下
    final exeDir = Platform.resolvedExecutable;
    final exeParent = Directory(exeDir).parent.path;
    _configDir = '$exeParent${Platform.pathSeparator}data';
    _configPath = '$_configDir${Platform.pathSeparator}config.yaml';

    // 确保配置目录存在
    await Directory(_configDir).create(recursive: true);

    // 核心路径：应用目录下的 AtlasCore_amd64.exe
    _corePath = '$exeParent${Platform.pathSeparator}$_coreName';
  }

  /// 从原始YAML提取指定顶层段的原始内容
  String _extractSection(String yaml, String sectionName) {
    final lines = yaml.split('\n');
    final sectionLines = <String>[];
    bool inSection = false;

    for (final line in lines) {
      if (!line.startsWith(' ') && !line.startsWith('\t')) {
        if (line.trim().startsWith('$sectionName:')) {
          inSection = true;
          continue;
        } else if (inSection && line.trim().contains(':') && !line.trim().startsWith('#') && !line.trim().startsWith('-')) {
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

    // 重建：保留相对缩进
    final buffer = StringBuffer();
    for (final line in sectionLines) {
      final trimmed = line.trimLeft();
      if (trimmed.isEmpty) continue;
      final delta = line.length - trimmed.length - minIndent;
      buffer.writeln('${' ' * (delta + 2)}$trimmed');
    }
    return buffer.toString().trimRight();
  }

  /// 从订阅YAML中只提取代理节点列表（名称列表，用于proxy-groups）
  List<String> _extractProxyNames(String rawYaml) {
    final names = <String>[];
    try {
      final yaml = loadYaml(rawYaml);
      if (yaml is Map) {
        final proxies = yaml['proxies'];
        if (proxies is List) {
          for (final p in proxies) {
            if (p is Map) {
              final name = p['name']?.toString();
              if (name != null && name.isNotEmpty) names.add(name);
            }
          }
        }
      }
    } catch (_) {}
    return names;
  }

  /// 生成Clash配置（订阅只取节点，规则和分流完全内置）
  String generateClashConfig(String rawYaml, AppSettings settings) {
    // 只从订阅提取代理节点
    final proxyNames = _extractProxyNames(rawYaml);
    final proxiesText = _extractSection(rawYaml, 'proxies');

    // 构建代理组列表（内置）
    final nodeListStr = proxyNames.map((n) => "'$n'").join(', ');

    final result = StringBuffer();
    result.writeln('# ===== SSRVPN 配置（规则内置，订阅仅加载节点） =====');
    result.writeln('mixed-port: ${settings.proxyPort}');
    result.writeln('socks-port: ${settings.socksPort}');
    result.writeln('allow-lan: false');
    result.writeln('mode: Rule');
    result.writeln('log-level: info');
    result.writeln("external-controller: '127.0.0.1:${settings.apiPort}'");
    result.writeln('ipv6: false');
    if (settings.apiSecret.isNotEmpty) {
      result.writeln('secret: "${settings.apiSecret}"');
    }
    
    // DNS配置
    result.writeln();
    result.writeln('dns:');
    result.writeln('  enable: true');
    result.writeln('  ipv6: false');
    result.writeln('  enhanced-mode: fake-ip');
    result.writeln('  fake-ip-range: 198.18.0.1/16');
    result.writeln('  default-nameserver:');
    result.writeln('    - 223.5.5.5');
    result.writeln('    - 119.29.29.29');
    result.writeln('  nameserver:');
    result.writeln('    - 223.5.5.5');
    result.writeln('    - 119.29.29.29');
    result.writeln('  fallback:');
    result.writeln('    - 8.8.8.8');
    result.writeln('    - 1.1.1.1');
    result.writeln('  fallback-filter:');
    result.writeln('    geoip: true');
    result.writeln('    geoip-code: CN');
    result.writeln('    ipcidr:');
    result.writeln('      - 240.0.0.0/4');
    
    // 代理节点
    result.writeln();
    result.writeln('proxies:');
    result.writeln(proxiesText);
    
    // 内置代理组
    result.writeln();
    result.writeln('proxy-groups:');
    result.writeln('  - name: PROXY');
    result.writeln('    type: select');
    result.writeln('    proxies:');
    for (final name in proxyNames) {
      result.writeln("      - '$name'");
    }
    result.writeln('  - name: 自动选择');
    result.writeln('    type: url-test');
    result.writeln('    proxies:');
    for (final name in proxyNames) {
      result.writeln("      - '$name'");
    }
    result.writeln("    url: 'http://www.gstatic.com/generate_204'");
    result.writeln('    interval: 300');
    result.writeln('  - name: 故障转移');
    result.writeln('    type: fallback');
    result.writeln('    proxies:');
    for (final name in proxyNames) {
      result.writeln("      - '$name'");
    }
    result.writeln("    url: 'http://www.gstatic.com/generate_204'");
    result.writeln('    interval: 300');
    
    // 内置分流规则
    result.writeln();
    result.writeln('rules:');
    result.writeln(_builtinRules());

    return result.toString();
  }

  /// 内置分流规则（国内直连 + GEOIP 分流）
  String _builtinRules() {
    return "  - 'DOMAIN-SUFFIX,cn,DIRECT'\n"
           "  - 'GEOIP,CN,DIRECT'\n"
           "  - 'GEOIP,LAN,DIRECT,no-resolve'\n"
           "  - 'MATCH,PROXY'\n";
  }

  /// 将配置写入文件
  Future<void> writeConfig(String configContent) async {
    final file = File(_configPath);
    await file.writeAsString(configContent);
  }

  /// 启动Clash核心
  Future<bool> start() async {
    if (_isRunning) {
      // 检查进程是否真的还活着
      if (_clashProcess != null) {
        try {
          if (await _healthCheck()) return true;
        } catch (_) {}
      }
      // 进程已死，清理状态
      _isRunning = false;
      _clashProcess = null;
      _statusTimer?.cancel();
    }

    try {
      // 检查核心文件是否存在
      if (!File(_corePath).existsSync()) {
        _log('错误: 找不到核心文件 $_corePath');
        return false;
      }

      _log('启动 Clash 核心...');
      _log('核心路径: $_corePath');
      _log('配置目录: $_configDir');

      // 启动进程
      _clashProcess = await Process.start(
        _corePath,
        ['-d', _configDir],
        workingDirectory: _configDir,
        mode: ProcessStartMode.normal,
      );

      // 监听输出
      _clashProcess!.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        _log('Clash: $line');
      });

      _clashProcess!.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        _log('Clash Error: $line');
      });

      // 等待核心启动（首次需下载MMDB，可能需要较长时间）
      bool healthy = false;
      for (int i = 0; i < 10; i++) {
        await Future.delayed(const Duration(seconds: 2));
        if (await _healthCheck()) {
          healthy = true;
          break;
        }
      }

      if (healthy) {
        _isRunning = true;
        _log('Clash 核心启动成功');
        onStatusChanged?.call();
        _startStatusMonitor();
        return true;
      } else {
        _log('Clash 核心启动失败: 健康检查未通过');
        await stop();
        return false;
      }
    } catch (e) {
      _log('启动 Clash 核心异常: $e');
      await stop();
      return false;
    }
  }

  /// 停止Clash核心
  Future<void> stop() async {
    if (_clashProcess != null) {
      try {
        _clashProcess!.kill(ProcessSignal.sigterm);
        await _clashProcess!.exitCode.timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            _clashProcess!.kill(ProcessSignal.sigkill);
            return -1;
          },
        );
      } catch (e) {
        _log('停止核心异常: $e');
      }
      _clashProcess = null;
    }
    _isRunning = false;
    _statusTimer?.cancel();
    _statusTimer = null;
    _log('Clash 核心已停止');
    onStatusChanged?.call();
  }

  /// 健康检查（使用TCP socket，兼容性更好）
  Future<bool> _healthCheck() async {
    try {
      final socket = await Socket.connect(
        '127.0.0.1',
        _settings.apiPort,
        timeout: const Duration(seconds: 3),
      );
      socket.destroy();
      return true;
    } catch (e) {
      return false;
    }
  }

  /// API基础URL
  String _apiUrl(String path) {
    final secret = _settings.apiSecret.isNotEmpty
        ? '?token=${_settings.apiSecret}'
        : '';
    final cleanPath = path.startsWith('/') ? path.substring(1) : path;
    return 'http://127.0.0.1:${_settings.apiPort}/$cleanPath$secret';
  }

  /// 获取代理节点列表
  Future<List<ProxyGroup>> getProxies() async {
    try {
      final response = await http.get(
        Uri.parse(_apiUrl('/proxies')),
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final proxies = data['proxies'] as Map<String, dynamic>? ?? {};

        final groups = <ProxyGroup>[];
        for (final entry in proxies.entries) {
          final proxyData = entry.value as Map<String, dynamic>;
          final type = proxyData['type'] as String? ?? '';

          if (type == 'Selector' ||
              type == 'URLTest' ||
              type == 'Fallback' ||
              type == 'LoadBalance') {
            // 这是一个代理组
            final allNames = (proxyData['all'] as List?)?.cast<String>() ?? [];
            final nodes = <ProxyNode>[];
            for (final name in allNames) {
              // 跳过其他组名
              if (proxies.containsKey(name) &&
                  (proxies[name] as Map<String, dynamic>)['type'] != 'Selector') {
                final nodeData = proxies[name] as Map<String, dynamic>;
                nodes.add(ProxyNode(
                  name: name,
                  type: nodeData['type'] as String? ?? 'unknown',
                  server: nodeData['server'] as String? ?? '',
                  port: nodeData['port'] as int? ?? 0,
                  group: entry.key,
                ));
              }
            }

            groups.add(ProxyGroup(
              name: entry.key,
              type: type.toLowerCase(),
              nodes: nodes,
              selectedNode: proxyData['now'] as String?,
            ));
          }
        }

        return groups;
      }
    } catch (e) {
      _log('获取代理列表失败: $e');
    }
    return [];
  }

  /// 测试节点延迟
  Future<int> testLatency(String proxyName, {int timeout = 5000}) async {
    try {
      final url = _apiUrl(
          '/proxies/${Uri.encodeComponent(proxyName)}/delay?timeout=$timeout&url=${Uri.encodeComponent('http://www.gstatic.com/generate_204')}');

      final response = await http.get(
        Uri.parse(url),
      ).timeout(Duration(milliseconds: timeout + 2000));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return data['delay'] as int? ?? -1;
      }
    } catch (e) {
      // 超时或失败
    }
    return -1;
  }

  /// 切换代理节点
  Future<bool> switchProxy(String groupName, String nodeName) async {
    try {
      final url = _apiUrl(
          '/proxies/${Uri.encodeComponent(groupName)}');

      final response = await http.put(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'name': nodeName}),
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200 || response.statusCode == 204) {
        // 关闭所有已有连接，强制新连接走新节点
        try {
          final connUrl = _apiUrl('/connections');
          await http.delete(Uri.parse(connUrl))
              .timeout(const Duration(seconds: 3));
        } catch (_) {}
        return true;
      }
      return false;
    } catch (e) {
      _log('切换代理失败: $e');
      return false;
    }
  }

  /// 切换代理模式
  Future<bool> switchMode(String mode) async {
    try {
      final url = _apiUrl('/configs');

      final response = await http.patch(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'mode': mode}),
      ).timeout(const Duration(seconds: 5));

      return response.statusCode == 200 || response.statusCode == 204;
    } catch (e) {
      _log('切换模式失败: $e');
      return false;
    }
  }

  /// 获取当前配置
  Future<Map<String, dynamic>?> getConfigs() async {
    try {
      final response = await http.get(
        Uri.parse(_apiUrl('/configs')),
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      _log('获取配置失败: $e');
    }
    return null;
  }

  /// 状态监控
  void _startStatusMonitor() {
    _statusTimer?.cancel();
    _statusTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (!_isRunning) return;
      final healthy = await _healthCheck();
      if (!healthy && _isRunning) {
        _isRunning = false;
        _log('Clash 核心连接丢失');
        onStatusChanged?.call();
        await stop();
      }
    });
  }

  void _log(String message) {
    onLog?.call(message);
  }

  /// 设置核心路径（用于用户自定义路径）
  void setCorePath(String path) {
    _corePath = path;
  }

  /// 检查核心文件是否存在
  bool get coreExists => File(_corePath).existsSync();

  String get corePath => _corePath;
  String get configDir => _configDir;
}
