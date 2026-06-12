import 'dart:io';
import 'package:flutter/material.dart';
import 'package:system_tray/system_tray.dart';
import '../models/app_settings.dart';

/// 系统托盘管理器
class TrayManager {
  static final TrayManager _instance = TrayManager._();
  factory TrayManager() => _instance;
  TrayManager._();

  final SystemTray _systemTray = SystemTray();
  bool _initialized = false;

  // 回调
  void Function()? onShowApp;
  void Function()? onQuit;
  void Function()? onConnectToggle;
  void Function(AppSettings?)? onSettingsChanged;
  bool Function()? isConnected;

  AppSettings? _settings;

  /// 初始化系统托盘
  Future<void> init(AppSettings settings) async {
    if (!Platform.isWindows) return;
    if (_initialized) return;
    _settings = settings;

    try {
      await _systemTray.initSystemTray(
        title: 'SSRVPN',
        iconPath: _getIconPath(),
      );

      await _buildMenu();
      _initialized = true;
    } catch (e) {
      // 托盘初始化失败
    }
  }

  /// 构建托盘菜单
  Future<void> _buildMenu() async {
    final connected = isConnected?.call() ?? false;

    final menu = Menu();

    await menu.buildFrom([
      MenuItemLabel(
        label: '显示主窗口',
        onClicked: (_) => onShowApp?.call(),
      ),
      MenuSeparator(),
      MenuItemLabel(
        label: connected ? '断开连接' : '连接',
        onClicked: (_) => onConnectToggle?.call(),
      ),
      MenuSeparator(),
      SubMenu(
        label: '代理模式',
        children: [
          MenuItemLabel(
            label: '全局模式',
            onClicked: (_) => _switchMode(ProxyMode.global),
          ),
          MenuItemLabel(
            label: '规则模式',
            onClicked: (_) => _switchMode(ProxyMode.rule),
          ),
          MenuItemLabel(
            label: '直连模式',
            onClicked: (_) => _switchMode(ProxyMode.direct),
          ),
        ],
      ),
      MenuSeparator(),
      MenuItemLabel(
        label: '退出 SSRVPN',
        onClicked: (_) => onQuit?.call(),
      ),
    ]);

    await _systemTray.setContextMenu(menu);
  }

  void _switchMode(ProxyMode mode) {
    if (_settings != null) {
      _settings!.proxyMode = mode;
    }
  }

  /// 刷新菜单（连接状态变更后）
  Future<void> refreshMenu() async {
    if (!_initialized) return;
    await _buildMenu();
  }

  /// 设置托盘提示文本
  Future<void> setToolTip(String text) async {
    if (!_initialized) return;
    try {
      await _systemTray.setToolTip(text);
    } catch (_) {}
  }

  /// 销毁托盘
  Future<void> destroy() async {
    if (!_initialized) return;
    try {
      await _systemTray.destroy();
    } catch (_) {}
    _initialized = false;
  }

  /// 获取图标路径
  String _getIconPath() {
    // 打包后的路径
    return 'assets/icon.png';
  }

  /// 更新设置引用
  void updateSettings(AppSettings settings) {
    _settings = settings;
  }
}

typedef VoidCallback = void Function();
