import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'models/app_settings.dart';
import 'services/settings_service.dart';
import 'services/clash_service.dart' as clash;
import 'services/subscription_service.dart';
import 'services/system_proxy_service.dart';
import 'screens/home_screen.dart';
import 'screens/subscription_screen.dart';
import 'screens/settings_screen.dart';
import 'theme/app_theme.dart';
import 'widgets/tray_manager.dart';

class SSRVpnApp extends StatefulWidget {
  const SSRVpnApp({super.key});
  @override
  State<SSRVpnApp> createState() => _SSRVpnAppState();
}

class _SSRVpnAppState extends State<SSRVpnApp> with WindowListener {
  int _currentIndex = 0;
  final TrayManager _trayManager = TrayManager();
  bool _appInitialized = false;
  late final SettingsService _settingsService;
  late final clash.ClashService _clashService;
  late final SubscriptionService _subscriptionService;
  late final SystemProxyService _systemProxyService;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _initApp();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _clashService.stop();
    _systemProxyService.clearSystemProxy();
    _trayManager.destroy();
    super.dispose();
  }

  Future<void> _initApp() async {
    await windowManager.ensureInitialized();
    final windowOptions = WindowOptions(
      size: const Size(940, 640),
      minimumSize: const Size(860, 540),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.normal,
      title: 'SSRVPN',
    );
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
    _settingsService = await SettingsService.getInstance();
    _clashService = clash.ClashService();
    await _clashService.init(_settingsService.settings);
    final appDataDir = await _getAppDataDir();
    _subscriptionService = await SubscriptionService.getInstance(appDataDir);
    _systemProxyService = SystemProxyService();
    _trayManager.onShowApp = _showApp;
    _trayManager.onQuit = _quitApp;
    _trayManager.onConnectToggle = _toggleConnection;
    _trayManager.isConnected = () => _clashService.isRunning;
    await _trayManager.init(_settingsService.settings);
    windowManager.setPreventClose(true);
    setState(() => _appInitialized = true);
  }

  Future<String> _getAppDataDir() async => _clashService.configDir;
  void _showApp() { windowManager.show(); windowManager.focus(); }

  Future<void> _quitApp() async {
    try { await _clashService.stop(); } catch (_) {}
    try { await _systemProxyService.clearSystemProxy(); } catch (_) {}
    try { await _trayManager.destroy(); } catch (_) {}
    try { await windowManager.destroy(); } catch (_) {}
    // 强制退出进程，防止残留
    if (Platform.isWindows) {
      // 先杀掉所有 AtlasCore 进程（按进程名）
      Process.run('taskkill', ['/F', '/IM', 'AtlasCore_amd64.exe']);
      // 再杀自身
      Process.run('taskkill', ['/F', '/PID', pid.toString()]);
    }
    SystemNavigator.pop();
    exit(0);
  }

  Future<void> _toggleConnection() async {
    if (_clashService.isRunning) {
      await _clashService.stop();
      await _systemProxyService.clearSystemProxy();
    } else {
      final rawYaml = _subscriptionService.rawYaml;
      if (rawYaml != null && rawYaml.isNotEmpty) {
        final config = _clashService.generateClashConfig(rawYaml, _settingsService.settings);
        await _clashService.writeConfig(config);
        await _clashService.start();
        if (_settingsService.settings.enableSystemProxy) {
          await _systemProxyService.setSystemProxy('127.0.0.1', _settingsService.settings.proxyPort);
        }
      }
    }
    setState(() {});
    _trayManager.refreshMenu();
  }

  @override
  void onWindowClose() {
    if (_settingsService.settings.closeToTray) {
      windowManager.hide();
    } else {
      _quitApp();
    }
  }

  @override
  void onWindowMinimize() {
    if (_settingsService.settings.minimizeToTray) {
      windowManager.hide();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_appInitialized) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        home: const Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(width: 32, height: 32, child: CircularProgressIndicator(strokeWidth: 2.5, color: AppTheme.primaryColor)),
                SizedBox(height: 20),
                Text('SSRVPN', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppTheme.darkTextPrimary)),
                SizedBox(height: 6),
                Text('Loading...', style: TextStyle(fontSize: 13, color: AppTheme.darkTextSecondary)),
              ],
            ),
          ),
        ),
      );
    }
    final isDark = _settingsService.settings.darkMode;
    return MultiProvider(
      providers: [
        Provider<SettingsService>.value(value: _settingsService),
        Provider<clash.ClashService>.value(value: _clashService),
        Provider<SubscriptionService>.value(value: _subscriptionService),
        Provider<SystemProxyService>.value(value: _systemProxyService),
        ChangeNotifierProvider<SettingsService>.value(value: _settingsService),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'SSRVPN',
        theme: AppTheme.darkTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
        home: _buildMainScreen(isDark),
      ),
    );
  }

  Widget _buildMainScreen(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [const Color(0xFF0B0D14), const Color(0xFF0F1119), const Color(0xFF111320), const Color(0xFF0E1018)]
              : [const Color(0xFFF8FAFC), const Color(0xFFF1F5F9), const Color(0xFFF8FAFC)],
        ),
      ),
      child: Row(
        children: [
          _buildSidebar(isDark),
          Expanded(
            child: IndexedStack(
              index: _currentIndex,
              children: const [HomeScreen(), SubscriptionScreen(), SettingsScreen()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar(bool isDark) {
    return Container(
      width: 72,
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withAlpha(6) : Colors.black.withAlpha(5),
        border: Border(right: BorderSide(color: isDark ? AppTheme.darkBorderLight : AppTheme.lightBorder, width: 1)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 24),
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [AppTheme.primaryColor, AppTheme.accentColor]),
              borderRadius: BorderRadius.circular(10),
              boxShadow: [BoxShadow(color: AppTheme.primaryColor.withAlpha(50), blurRadius: 12, offset: const Offset(0, 4))],
            ),
            child: const Icon(Icons.shield_rounded, color: Colors.white, size: 20),
          ),
          const SizedBox(height: 32),
          _NavItem(icon: Icons.home_rounded, label: '主页', isSelected: _currentIndex == 0, onTap: () => setState(() => _currentIndex = 0), isDark: isDark),
          const SizedBox(height: 4),
          _NavItem(icon: Icons.rss_feed_rounded, label: '订阅', isSelected: _currentIndex == 1, onTap: () => setState(() => _currentIndex = 1), isDark: isDark),
          const SizedBox(height: 4),
          _NavItem(icon: Icons.tune_rounded, label: '设置', isSelected: _currentIndex == 2, onTap: () => setState(() => _currentIndex = 2), isDark: isDark),
          const Spacer(),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final bool isDark;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 52,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryColor.withAlpha(isDark ? 20 : 15) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, size: 22, color: isSelected ? AppTheme.primaryColor : (isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextHint)),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(fontSize: 10, fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500, color: isSelected ? AppTheme.primaryColor : (isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextHint), decoration: TextDecoration.none)),
          ],
        ),
      ),
    );
  }
}
