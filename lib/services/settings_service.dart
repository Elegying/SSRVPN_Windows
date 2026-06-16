import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../models/app_settings.dart';

/// 设置持久化服务 (Windows 便携版)
///
/// 使用 JSON 文件存储设置，放在 exe 同级目录下，支持绿色免安装。
class SettingsService extends ChangeNotifier {
  static SettingsService? _instance;
  late AppSettings _settings;
  late String _settingsPath;
  late String _dataDir;
  String? _storageNotice;

  SettingsService._();

  static Future<SettingsService> getInstance() async {
    if (_instance == null) {
      _instance = SettingsService._();
      await _instance!._init();
    }
    return _instance!;
  }

  Future<void> _init() async {
    _dataDir = await _resolveDataDirectory();
    _settingsPath = '$_dataDir${Platform.pathSeparator}settings.json';

    await _load();
  }

  AppSettings get settings => _settings;
  String get dataDir => _dataDir;
  String? get storageNotice => _storageNotice;

  Future<String> _resolveDataDirectory() async {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final portableDir = '$exeDir${Platform.pathSeparator}ssrvpn';
    try {
      await _verifyWritableDirectory(portableDir);
      return portableDir;
    } catch (e) {
      final localAppData = Platform.environment['LOCALAPPDATA'];
      if (localAppData == null || localAppData.trim().isEmpty) {
        rethrow;
      }

      final fallbackDir =
          '$localAppData${Platform.pathSeparator}SSRVPN${Platform.pathSeparator}ssrvpn';
      await _verifyWritableDirectory(fallbackDir);
      await _migratePortableData(portableDir, fallbackDir);
      _storageNotice = '程序目录不可写，数据已改存到 $fallbackDir（原因: $e）';
      return fallbackDir;
    }
  }

  Future<void> _verifyWritableDirectory(String path) async {
    final directory = Directory(path);
    await directory.create(recursive: true);
    final probe = File(
      '$path${Platform.pathSeparator}.write_test_${pid}_${DateTime.now().microsecondsSinceEpoch}',
    );
    try {
      await probe.writeAsString('ok', flush: true);
    } finally {
      if (await probe.exists()) await probe.delete();
    }
  }

  Future<void> _migratePortableData(
    String portableDir,
    String fallbackDir,
  ) async {
    final source = Directory(portableDir);
    if (!await source.exists()) return;

    const fileNames = [
      'settings.json',
      'subscriptions.json',
      'subscription_cache.yaml',
      'config.yaml',
      'country.mmdb',
      'geoip.metadb',
    ];
    for (final name in fileNames) {
      final sourceFile = File('$portableDir${Platform.pathSeparator}$name');
      final targetFile = File('$fallbackDir${Platform.pathSeparator}$name');
      if (!await sourceFile.exists() || await targetFile.exists()) continue;
      try {
        await sourceFile.copy(targetFile.path);
      } catch (_) {
        // A single locked cache file should not block application startup.
      }
    }
  }

  Future<void> _load() async {
    final file = File(_settingsPath);
    if (await file.exists()) {
      try {
        final content = await file.readAsString();
        final json = jsonDecode(content) as Map<String, dynamic>;
        _settings = AppSettings.fromJson(json);
      } catch (e) {
        _settings = AppSettings();
      }
    } else {
      _settings = AppSettings();
    }

    // 首次启动生成随机 API secret
    if (_settings.apiSecret.isEmpty) {
      _settings.apiSecret = _generateSecret();
      await save();
    }
  }

  String _generateSecret() {
    final rand = Random.secure();
    return List.generate(
        16, (_) => rand.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  Future<void> save() async {
    final jsonStr = jsonEncode(_settings.toJson());
    final file = File(_settingsPath);
    final temp = File('$_settingsPath.tmp');
    await temp.writeAsString(jsonStr, flush: true);
    await temp.rename(file.path);
    notifyListeners();
  }

  Future<void> updateProxyPort(int port) async {
    _settings.proxyPort = port;
    await save();
  }

  Future<void> updateSocksPort(int port) async {
    _settings.socksPort = port;
    await save();
  }

  Future<void> updateApiPort(int port) async {
    _settings.apiPort = port;
    await save();
  }

  Future<void> updateApiSecret(String secret) async {
    _settings.apiSecret = secret;
    await save();
  }

  Future<void> updateProxyMode(ProxyMode mode) async {
    _settings.proxyMode = mode;
    await save();
  }

  Future<void> updateTunStack(String stack) async {
    _settings.tunStack = stack;
    await save();
  }

  Future<void> updateEnableTun(bool enable) async {
    _settings.enableTun = enable;
    await save();
  }

  Future<void> updateDarkMode(bool enabled) async {
    _settings.darkMode = enabled;
    await save();
  }

  Future<void> updateLatencyTestUrl(String url) async {
    _settings.latencyTestUrl = url;
    await save();
  }

  Future<void> updateLatencyTestTimeout(int ms) async {
    _settings.latencyTestTimeout = ms;
    await save();
  }

  Future<void> updateMinimizeToTray(bool minimize) async {
    _settings.minimizeToTray = minimize;
    await save();
  }

  Future<void> updateLastSelectedNodeName(String nodeName) async {
    _settings.lastSelectedNodeName = nodeName;
    await save();
  }

  Future<void> renameLastSelectedNode(
    String originalName,
    String updatedName,
  ) async {
    if (_settings.lastSelectedNodeName != originalName) return;
    _settings.lastSelectedNodeName = updatedName;
    await save();
  }
}
