import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_settings.dart';
import '../services/clash_service.dart';
import '../services/settings_service.dart';
import '../services/update_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_container.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _applyNetworkSetting(
    BuildContext context,
    Future<void> Function(SettingsService settings) update,
  ) async {
    final clash = context.read<ClashService>();
    final settings = context.read<SettingsService>();
    final wasRunning = clash.isRunning;
    if (wasRunning) await clash.stop();
    await update(settings);
    clash.updateSettings(settings.settings);

    if (wasRunning && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.fromLTRB(16, 0, 16, 16),
        content: Text('网络设置已更新，请重新连接')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<SettingsService>();
    final settings = service.settings;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor =
        isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary;
    final subtitleColor =
        isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppTheme.primaryColor, AppTheme.accentColor],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.settings_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  '设置',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: titleColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            GlassContainer(
              borderRadius: 18,
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '代理模式',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: titleColor,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '切换模式会断开当前连接，重新连接后生效',
                    style: TextStyle(fontSize: 12, color: subtitleColor),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<ProxyMode>(
                      segments: ProxyMode.values
                          .map(
                            (mode) => ButtonSegment(
                              value: mode,
                              label:
                                  Text(mode.chineseName.replaceAll('模式', '')),
                            ),
                          )
                          .toList(),
                      selected: {settings.proxyMode},
                      onSelectionChanged: (selection) {
                        _applyNetworkSetting(
                          context,
                          (service) => service.updateProxyMode(selection.first),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      'TUN 模式',
                      style: TextStyle(color: titleColor),
                    ),
                    subtitle: Text(
                      '代理所有流量，需要以管理员身份运行',
                      style: TextStyle(fontSize: 12, color: subtitleColor),
                    ),
                    value: settings.enableTun,
                    onChanged: (value) {
                      _applyNetworkSetting(
                        context,
                        (service) => service.updateEnableTun(value),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            GlassContainer(
              borderRadius: 18,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Column(
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '最小化到系统托盘',
                      style: TextStyle(color: titleColor),
                    ),
                    subtitle: Text(
                      '最小化或关闭窗口时保持后台运行',
                      style: TextStyle(fontSize: 12, color: subtitleColor),
                    ),
                    value: settings.minimizeToTray,
                    onChanged: service.updateMinimizeToTray,
                  ),
                  Divider(
                    height: 1,
                    color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '深色模式',
                      style: TextStyle(color: titleColor),
                    ),
                    value: settings.darkMode,
                    onChanged: service.updateDarkMode,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'SSRVPN ${UpdateService.appVersion}',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: subtitleColor),
            ),
          ],
        ),
      ),
    );
  }
}
