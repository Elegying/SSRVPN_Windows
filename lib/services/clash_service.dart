import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:yaml/yaml.dart';
import '../models/proxy_node.dart';
import '../models/app_settings.dart';
import 'system_proxy_service.dart';

/// Clash Meta 核心管理服务 (Windows 版)
///
/// 通过 spawn mihomo.exe 子进程启动核心，使用 REST API 控制。
/// 支持 TUN 模式（需管理员权限）和系统代理模式。
class ClashService {
  Process? _coreProcess;
  Timer? _statusTimer;
  Future<bool>? _startOperation;
  Future<void>? _stopOperation;
  bool _isRunning = false;

  AppSettings _settings = AppSettings();
  String _corePath = '';
  String _configDir = '';
  String _configPath = '';
  String _logBuffer = '';

  final SystemProxyService _proxyService = SystemProxyService();

  final Set<VoidCallback> _statusListeners = {};
  void Function(String message)? onLog;

  bool get isRunning => _isRunning;
  String get recentLogs => _logBuffer;
  String get configDir => _configDir;

  void updateSettings(AppSettings settings) {
    _settings = settings;
  }

  /// 初始化服务
  Future<void> init(AppSettings settings) async {
    _settings = settings;

    // 配置目录：放在 exe 同级目录下（便携模式）
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    _configDir = '$exeDir${Platform.pathSeparator}ssrvpn';
    _configPath = '$_configDir${Platform.pathSeparator}config.yaml';
    _corePath = '$exeDir${Platform.pathSeparator}mihomo.exe';
    await Directory(_configDir).create(recursive: true);
    await _proxyService.initialize(_configDir);
    await _terminateOrphanedCores();

    _log('配置目录: $_configDir');
    _log('核心路径: $_corePath');

    // 验证核心文件
    final coreFile = File(_corePath);
    if (await coreFile.exists()) {
      final size = await coreFile.length();
      _log('✅ 核心文件存在: ${(size / 1024 / 1024).toStringAsFixed(1)} MB');
    } else {
      _log('❌ 核心文件不存在: $_corePath');
      _log('请将 mihomo.exe 放到应用目录下');
    }

    // 预下载 MMDB 文件
    await _ensureMMDB();
  }

  /// Cleans up cores left behind if the previous app process was terminated.
  Future<void> _terminateOrphanedCores() async {
    if (!Platform.isWindows || _corePath.isEmpty) return;
    final encodedPath = base64Encode(utf8.encode(_corePath));
    final script = '''
\$target = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$encodedPath'))
Get-CimInstance Win32_Process -Filter "Name='mihomo.exe'" |
  Where-Object { \$_.ExecutablePath -eq \$target } |
  ForEach-Object { Stop-Process -Id \$_.ProcessId -Force -ErrorAction SilentlyContinue }
''';
    try {
      final result = await Process.run(
        'powershell',
        [
          '-NoLogo',
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          script,
        ],
      );
      if (result.exitCode == 0) {
        _log('已清理遗留的 Mihomo 进程');
      }
    } catch (e) {
      _log('清理遗留核心失败: $e');
    }
  }

  /// 预下载 MMDB 文件
  Future<void> _ensureMMDB() async {
    final metadbPath = '$_configDir${Platform.pathSeparator}geoip.metadb';
    final mmdbPath = '$_configDir${Platform.pathSeparator}country.mmdb';

    try {
      final m = File(metadbPath);
      if (await m.exists() && await m.length() > 1024 * 1024) {
        _log('✅ MMDB 已存在');
        return;
      }
      final g = File(mmdbPath);
      if (await g.exists() && await g.length() > 1024 * 1024) {
        _log('✅ MMDB 已存在');
        return;
      }
    } catch (_) {}

    // 从内置资源复制（gzip 压缩）
    try {
      await Directory(_configDir).create(recursive: true);
      final assetPath =
          '${File(Platform.resolvedExecutable).parent.path}${Platform.pathSeparator}data${Platform.pathSeparator}flutter_assets${Platform.pathSeparator}assets${Platform.pathSeparator}geoip.metadb.gz';
      final compressed = await File(assetPath).readAsBytes();
      final bytes = gzip.decode(compressed);
      final file = File(metadbPath);
      final temp = File('$metadbPath.tmp');
      await temp.writeAsBytes(bytes, flush: true);
      await temp.rename(file.path);
      _log(
          '✅ MMDB 已从内置资源解压 (${(bytes.length / 1024 / 1024).toStringAsFixed(1)} MB)');
    } catch (e) {
      _log('⚠️ MMDB 资源复制失败: $e');
      _log('❌ MMDB 不可用，GEOIP 规则将跳过');
    }
  }

  /// 提取指定段落
  String _extractSection(String yaml, String sectionName) {
    final lines = yaml.split('\n');
    final sectionLines = <String>[];
    bool inSection = false;

    for (final line in lines) {
      if (!line.startsWith(' ') && !line.startsWith('\t')) {
        if (line.trim().startsWith('$sectionName:')) {
          inSection = true;
          continue;
        } else if (inSection &&
            line.trim().contains(':') &&
            !line.trim().startsWith('#') &&
            !line.trim().startsWith('-')) {
          break;
        }
      }
      if (inSection) {
        sectionLines.add(line);
      }
    }

    int minIndent = 999;
    for (final line in sectionLines) {
      final t = line.trimLeft();
      if (t.isEmpty) continue;
      final indent = line.length - t.length;
      if (indent < minIndent) minIndent = indent;
    }
    if (minIndent == 999) minIndent = 0;

    final buffer = StringBuffer();
    for (final line in sectionLines) {
      final trimmed = line.trimLeft();
      if (trimmed.isEmpty) continue;
      final delta = line.length - trimmed.length - minIndent;
      buffer.writeln('${' ' * (delta + 2)}$trimmed');
    }
    return buffer.toString().trimRight();
  }

  /// 提取代理名称列表
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

  /// YAML 单引号字符串转义
  String _quote(String name) => "'${name.replaceAll("'", "''")}'";

  /// 生成 Clash 配置
  String generateClashConfig(String rawYaml, AppSettings settings) {
    final proxyNames = _extractProxyNames(rawYaml);
    final proxiesText = _extractSection(rawYaml, 'proxies');
    if (proxyNames.isEmpty || proxiesText.isEmpty) {
      throw Exception('订阅中没有可用节点，请先刷新订阅');
    }

    // 检查 MMDB
    final mmdbExists = (() {
      try {
        final m = File('$_configDir${Platform.pathSeparator}country.mmdb');
        if (m.existsSync() && m.lengthSync() > 1024 * 1024) return true;
        final g = File('$_configDir${Platform.pathSeparator}geoip.metadb');
        if (g.existsSync() && g.lengthSync() > 1024 * 1024) return true;
      } catch (_) {}
      return false;
    })();

    final result = StringBuffer();
    result.writeln('# ===== SSRVPN Windows =====');
    result.writeln('mixed-port: ${settings.proxyPort}');
    result.writeln('socks-port: ${settings.socksPort}');
    result.writeln('allow-lan: false');
    result.writeln('mode: ${settings.proxyMode.name}');
    result.writeln('log-level: info');
    result.writeln("external-controller: '127.0.0.1:${settings.apiPort}'");
    result.writeln('ipv6: false');
    if (settings.apiSecret.isNotEmpty) {
      result.writeln('secret: ${_quote(settings.apiSecret)}');
    }

    // TUN 模式配置
    result.writeln();
    result.writeln('tun:');
    result.writeln('  enable: ${settings.enableTun}');
    result.writeln('  stack: ${settings.tunStack}');
    result.writeln('  dns-hijack:');
    result.writeln('    - any:53');
    result.writeln('  auto-route: true');
    result.writeln('  auto-detect-interface: true');

    // DNS
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
    result.writeln('    - https://dns.alidns.com/dns-query');
    result.writeln('    - https://doh.pub/dns-query');
    result.writeln('    - 223.5.5.5');
    result.writeln('    - 119.29.29.29');
    result.writeln('  fallback:');
    result.writeln('    - https://dns.google/dns-query');
    result.writeln('    - https://cloudflare-dns.com/dns-query');
    result.writeln('    - 8.8.8.8');
    result.writeln('    - 1.1.1.1');
    result.writeln('  fallback-filter:');
    result.writeln('    geoip: true');
    result.writeln('    geoip-code: CN');
    result.writeln('    ipcidr:');
    result.writeln('      - 240.0.0.0/4');
    result.writeln('    domain:');
    result.writeln("      - '*.google.com'");
    result.writeln("      - '*.googlevideo.com'");
    result.writeln("      - '*.youtube.com'");
    result.writeln("      - '*.ytimg.com'");
    result.writeln("      - '*.ggpht.com'");
    result.writeln('  fake-ip-filter:');
    result.writeln("    - '*.lan'");
    result.writeln("    - '*.local'");
    result.writeln("    - '*.localhost'");
    result.writeln("    - '*.googlevideo.com'");
    result.writeln("    - '*.youtube.com'");
    result.writeln("    - '*.ytimg.com'");
    result.writeln("    - '*.ggpht.com'");
    result.writeln("    - '*.googleapis.com'");
    result.writeln("    - 'dns.google'");
    result.writeln("    - 'www.google.com'");

    // Proxies
    result.writeln();
    result.writeln('proxies:');
    result.writeln(proxiesText);

    // Proxy Groups
    result.writeln();
    result.writeln('proxy-groups:');
    result.writeln('  - name: PROXY');
    result.writeln('    type: select');
    result.writeln('    proxies:');
    for (final name in proxyNames) {
      result.writeln("      - ${_quote(name)}");
    }
    result.writeln('  - name: 自动选择');
    result.writeln('    type: url-test');
    result.writeln('    proxies:');
    for (final name in proxyNames) {
      result.writeln("      - ${_quote(name)}");
    }
    result.writeln('    url: ${_quote(settings.latencyTestUrl)}');
    result.writeln('    interval: 300');

    // Rules
    result.writeln();
    result.writeln('rules:');
    result.writeln("  - 'DOMAIN-SUFFIX,cn,DIRECT'");
    if (mmdbExists) {
      result.writeln("  - 'GEOIP,CN,DIRECT'");
      result.writeln("  - 'GEOIP,LAN,DIRECT,no-resolve'");
    }
    result.writeln("  - 'MATCH,PROXY'");

    return result.toString();
  }

  /// 写入配置
  Future<void> writeConfig(String configContent) async {
    final file = File(_configPath);
    final temp = File('$_configPath.tmp');
    await temp.writeAsString(configContent, flush: true);
    await temp.rename(file.path);
  }

  /// 启动核心
  Future<bool> start() {
    final current = _startOperation;
    if (current != null) return current;

    final operation = _startInternal();
    _startOperation = operation;
    operation.then<void>(
      (_) => _clearStartOperation(operation),
      onError: (_, __) => _clearStartOperation(operation),
    );
    return operation;
  }

  Future<bool> _startInternal() async {
    final stopping = _stopOperation;
    if (stopping != null) await stopping;

    if (_isRunning) {
      try {
        if (await _healthCheck()) return true;
      } catch (_) {}
      _isRunning = false;
      _statusTimer?.cancel();
    }

    try {
      _log('🚀 启动 Mihomo...');

      // 检查核心文件
      if (!File(_corePath).existsSync()) {
        _log('❌ 核心文件不存在: $_corePath');
        _log('请下载 mihomo-windows-amd64 并重命名为 mihomo.exe 放到应用目录');
        return false;
      }

      if (!File(_configPath).existsSync()) {
        _log('❌ 配置文件不存在: $_configPath');
        return false;
      }

      // 创建 tmp 目录
      final tmpDir = '$_configDir${Platform.pathSeparator}tmp';
      await Directory(tmpDir).create(recursive: true);

      // 启动 mihomo 子进程（所有数据都在便携目录内）
      _coreProcess = await Process.start(
        _corePath,
        ['-d', _configDir, '-f', _configPath],
        mode: ProcessStartMode.normal,
        includeParentEnvironment: true,
        environment: {
          'TMPDIR': tmpDir,
          'TMP': tmpDir,
          'TEMP': tmpDir,
        },
      );

      // 监听子进程输出
      _coreProcess!.stdout.transform(utf8.decoder).listen((data) {
        _log(data.trim());
      });
      _coreProcess!.stderr.transform(utf8.decoder).listen((data) {
        _log('[stderr] ${data.trim()}');
      });

      // 监听子进程退出
      _coreProcess!.exitCode.then((code) {
        if (_isRunning) {
          _isRunning = false;
          _log('核心进程退出，退出码: $code');
          _notifyStatusChanged();
          _proxyService.clearSystemProxy();
        }
      });

      // 等待核心启动
      await Future.delayed(const Duration(seconds: 2));

      // 健康检查
      final healthy = await _healthCheck();
      if (healthy) {
        _isRunning = true;
        _log('✅ Mihomo 启动成功');

        // 设置系统代理（非 TUN 模式时）
        if (!_settings.enableTun) {
          final proxySet = await _proxyService.setSystemProxy(
              '127.0.0.1', _settings.proxyPort);
          if (proxySet) {
            _log('✅ 系统代理已设置');
          } else {
            _log('❌ 系统代理设置失败，连接已取消');
            await _stopInternal();
            return false;
          }
        }

        _notifyStatusChanged();
        _startStatusMonitor();
        return true;
      } else {
        _log('❌ 核心启动后健康检查失败');
        await _stopInternal();
        return false;
      }
    } catch (e, stack) {
      _log('❌ 启动异常: $e');
      _log('堆栈: $stack');
      await _stopInternal();
      return false;
    }
  }

  /// 停止核心
  Future<void> stop() {
    final current = _stopOperation;
    if (current != null) return current;

    final operation = _stopAfterStart();
    _stopOperation = operation;
    operation.then<void>(
      (_) => _clearStopOperation(operation),
      onError: (_, __) => _clearStopOperation(operation),
    );
    return operation;
  }

  Future<void> _stopAfterStart() async {
    final starting = _startOperation;
    if (starting != null) await starting;
    await _stopInternal();
  }

  Future<void> _stopInternal() async {
    _statusTimer?.cancel();
    _statusTimer = null;

    if (_coreProcess != null) {
      try {
        _coreProcess!.kill(ProcessSignal.sigterm);
        // 等待进程退出
        await _coreProcess!.exitCode.timeout(
          const Duration(seconds: 3),
          onTimeout: () {
            _coreProcess!.kill(ProcessSignal.sigkill);
            return -1;
          },
        );
      } catch (e) {
        _log('停止异常: $e');
      }
      _coreProcess = null;
    }

    // 清除系统代理（在进程停止后执行）
    await _proxyService.clearSystemProxy();

    _isRunning = false;
    _notifyStatusChanged();
    _log('核心已停止');
  }

  void _clearStartOperation(Future<bool> operation) {
    if (identical(_startOperation, operation)) {
      _startOperation = null;
    }
  }

  void _clearStopOperation(Future<void> operation) {
    if (identical(_stopOperation, operation)) {
      _stopOperation = null;
    }
  }

  /// 健康检查（使用 HTTP 请求验证 API 可用性）
  Future<bool> _healthCheck() async {
    try {
      final url = Uri.parse('http://127.0.0.1:${_settings.apiPort}/version');
      final response = await http
          .get(url, headers: _apiHeaders())
          .timeout(const Duration(seconds: 3));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  String _apiUrl(String path) {
    final cleanPath = path.startsWith('/') ? path.substring(1) : path;
    return 'http://127.0.0.1:${_settings.apiPort}/$cleanPath';
  }

  Map<String, String> _apiHeaders([Map<String, String>? extra]) {
    return {
      if (_settings.apiSecret.isNotEmpty)
        'Authorization': 'Bearer ${_settings.apiSecret}',
      ...?extra,
    };
  }

  /// 测试延迟 (TCP 连接)
  Future<int> testLatency(String server, int port,
      {int timeoutMs = 5000}) async {
    final stopwatch = Stopwatch()..start();
    try {
      final socket = await Socket.connect(
        server,
        port,
        timeout: Duration(milliseconds: timeoutMs),
      );
      socket.destroy();
      stopwatch.stop();
      return stopwatch.elapsedMilliseconds;
    } catch (_) {
      return -1;
    }
  }

  /// 批量测速
  Future<void> testAllLatencies(
    List<ProxyNode> nodes,
    void Function(String name, int latency) onResult, {
    int concurrency = 10,
    int timeoutMs = 5000,
  }) async {
    for (var i = 0; i < nodes.length; i += concurrency) {
      final batch = nodes.skip(i).take(concurrency).toList();
      final results = await Future.wait(
        batch.map((n) => testLatency(n.server, n.port, timeoutMs: timeoutMs)),
      );
      for (var j = 0; j < batch.length; j++) {
        onResult(batch[j].name, results[j]);
      }
    }
  }

  /// 切换代理节点
  Future<bool> switchProxy(String groupName, String nodeName) async {
    try {
      final url = _apiUrl('/proxies/${Uri.encodeComponent(groupName)}');
      _log('切换代理: group=$groupName, node=$nodeName');
      _log('API URL: $url');

      final response = await http
          .put(
            Uri.parse(url),
            headers: _apiHeaders({'Content-Type': 'application/json'}),
            body: jsonEncode({'name': nodeName}),
          )
          .timeout(const Duration(seconds: 5));

      _log('API 响应: ${response.statusCode} ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 204) {
        _log('✅ 代理切换成功: $nodeName');
        // 断开现有连接，使新代理生效
        try {
          await http
              .delete(
                Uri.parse(_apiUrl('/connections')),
                headers: _apiHeaders(),
              )
              .timeout(const Duration(seconds: 3));
          _log('✅ 已断开旧连接');
        } catch (e) {
          _log('断开旧连接失败 (可忽略): $e');
        }
        return true;
      }
      _log('❌ 代理切换失败: HTTP ${response.statusCode}');
      return false;
    } catch (e) {
      _log('❌ 切换代理异常: $e');
      return false;
    }
  }

  bool _healthCheckInProgress = false;

  void _startStatusMonitor() {
    _statusTimer?.cancel();
    _statusTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (!_isRunning || _healthCheckInProgress) return;
      _healthCheckInProgress = true;
      try {
        final healthy = await _healthCheck();
        if (!healthy && _isRunning) {
          _isRunning = false;
          _log('核心连接丢失');
          _notifyStatusChanged();
          await stop();
        }
      } finally {
        _healthCheckInProgress = false;
      }
    });
  }

  void _log(String message) {
    _logBuffer = '$message\n$_logBuffer';
    if (_logBuffer.length > 10000) _logBuffer = _logBuffer.substring(0, 10000);
    onLog?.call(message);
    debugPrint('[Clash] $message');
  }

  void addStatusListener(VoidCallback listener) {
    _statusListeners.add(listener);
  }

  void removeStatusListener(VoidCallback listener) {
    _statusListeners.remove(listener);
  }

  void _notifyStatusChanged() {
    for (final listener in List<VoidCallback>.from(_statusListeners)) {
      listener();
    }
  }

  void setCorePath(String path) => _corePath = path;
  bool get coreExists => File(_corePath).existsSync();
  String get corePath => _corePath;
}
