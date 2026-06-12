import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_settings.dart';

/// 设置持久化服务
class SettingsService extends ChangeNotifier {
  static const _key = 'app_settings';
  static SettingsService? _instance;
  late SharedPreferences _prefs;
  late AppSettings _settings;

  SettingsService._();

  static Future<SettingsService> getInstance() async {
    if (_instance == null) {
      _instance = SettingsService._();
      _instance!._prefs = await SharedPreferences.getInstance();
      _instance!._load();
    }
    return _instance!;
  }

  AppSettings get settings => _settings;

  void _load() {
    final jsonStr = _prefs.getString(_key);
    if (jsonStr != null) {
      try {
        final json = jsonDecode(jsonStr) as Map<String, dynamic>;
        _settings = AppSettings.fromJson(json);
      } catch (e) {
        _settings = AppSettings();
      }
    } else {
      _settings = AppSettings();
    }
  }

  Future<void> save() async {
    final jsonStr = jsonEncode(_settings.toJson());
    await _prefs.setString(_key, jsonStr);
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

  Future<void> updateTunMode(bool enabled) async {
    _settings.tunMode = enabled;
    await save();
  }

  Future<void> updateTunStack(String stack) async {
    _settings.tunStack = stack;
    await save();
  }

  Future<void> updateEnableSystemProxy(bool enabled) async {
    _settings.enableSystemProxy = enabled;
    await save();
  }

  Future<void> updateStartOnBoot(bool enabled) async {
    _settings.startOnBoot = enabled;
    await save();
  }

  Future<void> updateStartMinimized(bool enabled) async {
    _settings.startMinimized = enabled;
    await save();
  }

  Future<void> updateMinimizeToTray(bool enabled) async {
    _settings.minimizeToTray = enabled;
    await save();
  }

  Future<void> updateCloseToTray(bool enabled) async {
    _settings.closeToTray = enabled;
    await save();
  }

  Future<void> updateDarkMode(bool enabled) async {
    _settings.darkMode = enabled;
    await save();
  }

  Future<void> updateAutoUpdateSubscription(bool enabled) async {
    _settings.autoUpdateSubscription = enabled;
    await save();
  }

  Future<void> updateUpdateIntervalHours(int hours) async {
    _settings.updateIntervalHours = hours;
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
}
