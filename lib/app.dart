import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'services/settings_service.dart';
import 'services/clash_service.dart' as clash;
import 'services/subscription_service.dart';
import 'services/tray_manager.dart';
import 'screens/home_screen.dart';
import 'screens/subscription_screen.dart';
import 'screens/unlock_test_screen.dart';
import 'theme/app_theme.dart';
import 'widgets/liquid_glass.dart';

class SSRVpnApp extends StatefulWidget {
  const SSRVpnApp({super.key});
  @override
  State<SSRVpnApp> createState() => _SSRVpnAppState();
}

class _SSRVpnAppState extends State<SSRVpnApp> with WindowListener {
  int _currentIndex = 0;
  bool _appInitialized = false;
  bool _initError = false;
  String _initErrorMsg = '';
  SettingsService? _settingsService;
  clash.ClashService? _clashService;
  SubscriptionService? _subscriptionService;
  final TrayManager _trayManager = TrayManager();
  bool _isQuitting = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _initApp();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _clashService?.removeStatusListener(_handleCoreStatusChanged);
    _clashService?.stop();
    _trayManager.destroy();
    super.dispose();
  }

  Future<void> _initApp() async {
    try {
      _settingsService = await SettingsService.getInstance();
      _clashService = clash.ClashService();
      await _clashService!
          .init(
            _settingsService!.settings,
            dataDir: _settingsService!.dataDir,
            storageNotice: _settingsService!.storageNotice,
          )
          .timeout(
            const Duration(seconds: 90),
            onTimeout: () => throw TimeoutException('核心服务初始化超时（90秒）'),
          );
      _clashService!.addStatusListener(_handleCoreStatusChanged);
      final appDataDir = _clashService!.configDir;
      _subscriptionService =
          await SubscriptionService.getInstance(appDataDir).timeout(
        const Duration(seconds: 30),
        onTimeout: () => throw TimeoutException('订阅服务初始化超时（30秒）'),
      );

      // 初始化系统托盘
      await _initTray();

      if (mounted) setState(() => _appInitialized = true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _initError = true;
          _initErrorMsg = e.toString();
        });
      }
    }
  }

  Future<void> _initTray() async {
    _trayManager.onShowApp = () async {
      await windowManager.show();
      await windowManager.restore();
      await windowManager.focus();
    };
    _trayManager.onHideApp = () async {
      await windowManager.hide();
    };
    _trayManager.onQuit = () async {
      await _quitApp();
    };
    _trayManager.onConnectToggle = () async {
      try {
        if (_clashService == null) return;
        if (_clashService!.isRunning) {
          await _clashService!.stop();
        } else {
          final rawYaml = _subscriptionService?.rawYaml;
          if (rawYaml != null && rawYaml.trim().isNotEmpty) {
            final preferredNodeName = _defaultNodeName();
            final runtimeSettings = await _clashService!.prepareForStart(
              _settingsService!.settings,
            );
            final config = _clashService!.generateClashConfig(
              rawYaml,
              runtimeSettings,
              preferredNodeName: preferredNodeName,
            );
            await _clashService!.writeConfig(config);
            final started = await _clashService!.start();
            if (started && preferredNodeName != null) {
              final switched =
                  await _clashService!.switchProxy('PROXY', preferredNodeName);
              if (switched) {
                await _settingsService!
                    .updateLastSelectedNodeName(preferredNodeName);
              }
            }
          }
        }
      } catch (e) {
        debugPrint('[Tray] 连接切换失败: $e');
      } finally {
        await _trayManager.refreshMenu();
      }
    };
    _trayManager.isConnected = () => _clashService?.isRunning ?? false;

    await _trayManager.init();
  }

  String? _defaultNodeName() {
    final nodes = _subscriptionService?.allNodes ?? const [];
    if (nodes.isEmpty) return null;
    final remembered = _settingsService?.settings.lastSelectedNodeName;
    if (remembered != null &&
        remembered.isNotEmpty &&
        nodes.any((node) => node.name == remembered)) {
      return remembered;
    }
    return nodes.first.name;
  }

  void _handleCoreStatusChanged() {
    _trayManager.refreshMenu();
  }

  Future<void> _quitApp() async {
    if (_isQuitting) return;
    _isQuitting = true;
    await _settingsService?.flush();
    await _clashService?.stop();
    await _trayManager.destroy();
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }

  // ── WindowListener ──

  /// 最小化按钮 → 托盘就绪时隐藏到托盘，否则正常最小化
  @override
  void onWindowMinimize() async {
    final minimizeToTray = _settingsService?.settings.minimizeToTray ?? true;
    if (minimizeToTray && _trayManager.isReady) {
      await windowManager.hide();
    }
  }

  /// 关闭按钮 → 按设置隐藏到托盘，或彻底退出
  @override
  void onWindowClose() async {
    if (_isQuitting) return;
    final minimizeToTray = _settingsService?.settings.minimizeToTray ?? true;
    if (minimizeToTray && _trayManager.isReady) {
      await windowManager.hide();
      return;
    }
    await _quitApp();
  }

  @override
  void onWindowFocus() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (_initError) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        home: Scaffold(
          backgroundColor: const Color(0xFF0B0D14),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: AppTheme.errorColor.withValues(alpha: 20 / 255),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.error_outline,
                        size: 36, color: AppTheme.errorColor),
                  ),
                  const SizedBox(height: 24),
                  const Text('初始化失败',
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.darkTextPrimary)),
                  const SizedBox(height: 10),
                  Text(_initErrorMsg,
                      style: const TextStyle(
                          fontSize: 14, color: AppTheme.darkTextSecondary),
                      textAlign: TextAlign.center),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: 140,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _initError = false;
                          _appInitialized = false;
                        });
                        _initApp();
                      },
                      style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12))),
                      child: const Text('重试',
                          style: TextStyle(color: Colors.white, fontSize: 15)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (!_appInitialized) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        home: const Scaffold(
          backgroundColor: Color(0xFF0B0D14),
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                    width: 40,
                    height: 40,
                    child: CircularProgressIndicator(
                        strokeWidth: 3, color: AppTheme.primaryColor)),
                SizedBox(height: 24),
                Text('SSRVPN',
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.darkTextPrimary,
                        letterSpacing: 1)),
                SizedBox(height: 10),
                Text('正在初始化...',
                    style: TextStyle(
                        fontSize: 15, color: AppTheme.darkTextSecondary)),
              ],
            ),
          ),
        ),
      );
    }

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsService>.value(value: _settingsService!),
        Provider<clash.ClashService>.value(value: _clashService!),
        ChangeNotifierProvider<SubscriptionService>.value(
            value: _subscriptionService!),
      ],
      child: Consumer<SettingsService>(
        builder: (context, settingsService, _) {
          final isDark = settingsService.settings.darkMode;
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            title: 'SSRVPN',
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
            home: _buildMainScreen(isDark),
          );
        },
      ),
    );
  }

  Widget _buildMainScreen(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isDark
              ? [
                  const Color(0xFF0B0D14),
                  const Color(0xFF0F1119),
                  const Color(0xFF111320)
                ]
              : [const Color(0xFFF8FAFC), const Color(0xFFF1F5F9)],
        ),
      ),
      child: Column(
        children: [
          Expanded(
            child: IndexedStack(
              index: _currentIndex,
              children: const [
                HomeScreen(),
                SubscriptionScreen(),
                UnlockTestScreen(),
              ],
            ),
          ),
          _buildBottomNav(isDark),
        ],
      ),
    );
  }

  Widget _buildBottomNav(bool isDark) {
    return LiquidGlassNavBar(
      currentIndex: _currentIndex,
      onTap: (index) => setState(() => _currentIndex = index),
      items: const [
        NavItem(
          icon: Icons.home_outlined,
          activeIcon: Icons.home_rounded,
          label: '主页',
        ),
        NavItem(
          icon: Icons.rss_feed_outlined,
          activeIcon: Icons.rss_feed_rounded,
          label: '订阅',
        ),
        NavItem(
          icon: Icons.fact_check_outlined,
          activeIcon: Icons.fact_check_rounded,
          label: '解锁',
        ),
      ],
    );
  }
}
