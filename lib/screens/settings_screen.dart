import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/app_settings.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_container.dart';

/// 设置页面 - 液态玻璃风格
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _proxyPortController;
  late TextEditingController _socksPortController;
  late TextEditingController _apiPortController;
  late TextEditingController _apiSecretController;
  late TextEditingController _latencyUrlController;
  late TextEditingController _latencyTimeoutController;

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsService>().settings;
    _proxyPortController = TextEditingController(text: '${settings.proxyPort}');
    _socksPortController = TextEditingController(text: '${settings.socksPort}');
    _apiPortController = TextEditingController(text: '${settings.apiPort}');
    _apiSecretController = TextEditingController(text: settings.apiSecret);
    _latencyUrlController = TextEditingController(text: settings.latencyTestUrl);
    _latencyTimeoutController =
        TextEditingController(text: '${settings.latencyTestTimeout}');
  }

  @override
  void dispose() {
    _proxyPortController.dispose();
    _socksPortController.dispose();
    _apiPortController.dispose();
    _apiSecretController.dispose();
    _latencyUrlController.dispose();
    _latencyTimeoutController.dispose();
    super.dispose();
  }

  Future<void> _savePort(String field, int? value) async {
    if (value == null || value < 1 || value > 65535) return;
    final settingsService = context.read<SettingsService>();
    switch (field) {
      case 'proxy':
        await settingsService.updateProxyPort(value);
        break;
      case 'socks':
        await settingsService.updateSocksPort(value);
        break;
      case 'api':
        await settingsService.updateApiPort(value);
        break;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('端口已更新'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsService = context.watch<SettingsService>();
    final settings = settingsService.settings;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 标题
              _buildHeader(isDark),
              const SizedBox(height: 24),

              // 代理设置
              _buildSectionTitle('代理设置', isDark),
              const SizedBox(height: 10),
              _buildGlassSection(isDark, [
                _buildPortField('HTTP/SOCKS 混合端口', '默认 7890',
                    _proxyPortController,
                    isDark: isDark,
                    onSubmitted: (v) => _savePort('proxy', int.tryParse(v))),
                const SizedBox(height: 12),
                _buildPortField(
                    'SOCKS5 端口', '默认 7891', _socksPortController,
                    isDark: isDark,
                    onSubmitted: (v) => _savePort('socks', int.tryParse(v))),
                const SizedBox(height: 12),
                _buildPortField(
                    'API 控制端口', '默认 9090', _apiPortController,
                    isDark: isDark,
                    onSubmitted: (v) => _savePort('api', int.tryParse(v))),
                const SizedBox(height: 12),
                _buildTextField('API 密钥（可选）', '留空则无需认证',
                    _apiSecretController,
                    isDark: isDark,
                    onSubmitted: (v) async {
                  await settingsService.updateApiSecret(v);
                }),
              ]),
              const SizedBox(height: 20),

              // TUN 模式
              _buildSectionTitle('TUN 模式', isDark),
              const SizedBox(height: 10),
              _buildGlassSection(isDark, [
                _buildSwitchTile(
                  'TUN 模式',
                  '启用虚拟网卡代理所有流量',
                  settings.tunMode,
                  (v) => settingsService.updateTunMode(v),
                  isDark: isDark,
                ),
                if (settings.tunMode) ...[
                  Divider(color: Colors.white.withAlpha(isDark ? 10 : 20)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text('TUN 协议栈: ',
                          style: TextStyle(
                            fontSize: 14,
                            color: isDark
                                ? Colors.white.withAlpha(160)
                                : AppTheme.lightTextPrimary,
                          )),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(
                                value: 'gvisor', label: Text('gVisor')),
                            ButtonSegment(
                                value: 'system', label: Text('System')),
                            ButtonSegment(
                                value: 'mixed', label: Text('Mixed')),
                          ],
                          selected: {settings.tunStack},
                          onSelectionChanged: (v) async {
                            await settingsService.updateTunStack(v.first);
                          },
                          style: ButtonStyle(
                            visualDensity: VisualDensity.compact,
                            textStyle: WidgetStateProperty.all(
                              const TextStyle(fontSize: 12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ]),
              const SizedBox(height: 20),

              // 系统设置
              _buildSectionTitle('系统设置', isDark),
              const SizedBox(height: 10),
              _buildGlassSection(isDark, [
                _buildSwitchTile(
                  '设置系统代理',
                  '连接时自动配置Windows系统代理',
                  settings.enableSystemProxy,
                  (v) => settingsService.updateEnableSystemProxy(v),
                  isDark: isDark,
                ),
                _buildSwitchTile(
                  '开机启动',
                  'Windows启动时自动运行SSRVPN',
                  settings.startOnBoot,
                  (v) => settingsService.updateStartOnBoot(v),
                  isDark: isDark,
                ),
                _buildSwitchTile(
                  '启动时最小化',
                  '程序启动时直接最小化到托盘',
                  settings.startMinimized,
                  (v) => settingsService.updateStartMinimized(v),
                  isDark: isDark,
                ),
                _buildSwitchTile(
                  '最小化到托盘',
                  '点击最小化时隐藏到系统托盘',
                  settings.minimizeToTray,
                  (v) => settingsService.updateMinimizeToTray(v),
                  isDark: isDark,
                ),
                _buildSwitchTile(
                  '关闭到托盘',
                  '点击关闭按钮时隐藏到托盘而非退出',
                  settings.closeToTray,
                  (v) => settingsService.updateCloseToTray(v),
                  isDark: isDark,
                ),
              ]),
              const SizedBox(height: 20),

              // 外观
              _buildSectionTitle('外观', isDark),
              const SizedBox(height: 10),
              _buildGlassSection(isDark, [
                _buildSwitchTile(
                  '深色模式',
                  '使用深色主题（默认）',
                  settings.darkMode,
                  (v) => settingsService.updateDarkMode(v),
                  isDark: isDark,
                ),
              ]),
              const SizedBox(height: 20),

              // 订阅设置
              _buildSectionTitle('订阅设置', isDark),
              const SizedBox(height: 10),
              _buildGlassSection(isDark, [
                _buildSwitchTile(
                  '自动更新订阅',
                  '定期自动刷新订阅内容',
                  settings.autoUpdateSubscription,
                  (v) => settingsService.updateAutoUpdateSubscription(v),
                  isDark: isDark,
                ),
                if (settings.autoUpdateSubscription) ...[
                  Divider(color: Colors.white.withAlpha(isDark ? 10 : 20)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text('更新间隔: ',
                          style: TextStyle(
                            fontSize: 14,
                            color: isDark
                                ? Colors.white.withAlpha(160)
                                : AppTheme.lightTextPrimary,
                          )),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SegmentedButton<int>(
                          segments: const [
                            ButtonSegment(value: 6, label: Text('6小时')),
                            ButtonSegment(value: 12, label: Text('12小时')),
                            ButtonSegment(value: 24, label: Text('24小时')),
                            ButtonSegment(value: 48, label: Text('48小时')),
                          ],
                          selected: {settings.updateIntervalHours},
                          onSelectionChanged: (v) async {
                            await settingsService
                                .updateUpdateIntervalHours(v.first);
                          },
                          style: ButtonStyle(
                            visualDensity: VisualDensity.compact,
                            textStyle: WidgetStateProperty.all(
                              const TextStyle(fontSize: 12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ]),
              const SizedBox(height: 20),

              // 延迟测试
              _buildSectionTitle('延迟测试', isDark),
              const SizedBox(height: 10),
              _buildGlassSection(isDark, [
                _buildTextField(
                  '测速 URL',
                  '用于节点延迟测试的URL',
                  _latencyUrlController,
                  isDark: isDark,
                  onSubmitted: (v) async {
                    if (v.isNotEmpty) {
                      await settingsService.updateLatencyTestUrl(v);
                    }
                  },
                ),
                const SizedBox(height: 12),
                _buildTextField(
                  '测速超时 (毫秒)',
                  '默认 5000',
                  _latencyTimeoutController,
                  isDark: isDark,
                  keyboardType: TextInputType.number,
                  onSubmitted: (v) async {
                    final ms = int.tryParse(v);
                    if (ms != null && ms > 0) {
                      await settingsService.updateLatencyTestTimeout(ms);
                    }
                  },
                ),
              ]),
              const SizedBox(height: 20),

              // 关于
              _buildSectionTitle('关于', isDark),
              const SizedBox(height: 10),
              GlassContainer(
                borderRadius: 18,
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppTheme.primaryColor, AppTheme.accentColor],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Center(
                        child: Text(
                          'SSR',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'SSRVPN',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: isDark
                                  ? Colors.white
                                  : AppTheme.lightTextPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'By: 两颗西柚',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? Colors.white.withAlpha(100)
                                  : AppTheme.lightTextSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(bool isDark) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppTheme.primaryColor, Color(0xFF8B5CF6)],
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.settings, color: Colors.white, size: 20),
        ),
        const SizedBox(width: 14),
        Text(
          '设置',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : AppTheme.lightTextPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String title, bool isDark) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: isDark
            ? Colors.white.withAlpha(160)
            : AppTheme.lightTextPrimary,
      ),
    );
  }

  Widget _buildGlassSection(bool isDark, List<Widget> children) {
    return GlassContainer(
      borderRadius: 18,
      padding: const EdgeInsets.all(18),
      child: Column(children: children),
    );
  }

  Widget _buildSwitchTile(
    String title,
    String subtitle,
    bool value,
    ValueChanged<bool> onChanged, {
    required bool isDark,
  }) {
    return SwitchListTile(
      title: Text(
        title,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: isDark ? Colors.white : AppTheme.lightTextPrimary,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontSize: 12,
          color: isDark
              ? Colors.white.withAlpha(100)
              : AppTheme.lightTextSecondary,
        ),
      ),
      value: value,
      onChanged: onChanged,
      contentPadding: EdgeInsets.zero,
      activeColor: AppTheme.primaryColor,
    );
  }

  Widget _buildPortField(
    String label,
    String hint,
    TextEditingController controller, {
    required bool isDark,
    ValueChanged<String>? onSubmitted,
  }) {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Colors.white.withAlpha(180) : AppTheme.lightTextPrimary,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 1,
          child: TextField(
            controller: controller,
            decoration: InputDecoration(
              hintText: hint,
              isDense: true,
              filled: true,
              fillColor: isDark
                  ? Colors.white.withAlpha(8)
                  : Colors.white.withAlpha(40),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: Colors.white.withAlpha(isDark ? 15 : 30),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: Colors.white.withAlpha(isDark ? 15 : 30),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: AppTheme.primaryColor.withAlpha(120),
                  width: 1.5,
                ),
              ),
            ),
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isDark ? Colors.white : AppTheme.lightTextPrimary,
            ),
            onSubmitted: onSubmitted,
          ),
        ),
      ],
    );
  }

  Widget _buildTextField(
    String label,
    String hint,
    TextEditingController controller, {
    required bool isDark,
    TextInputType? keyboardType,
    ValueChanged<String>? onSubmitted,
  }) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        isDense: true,
        filled: true,
        fillColor: isDark
            ? Colors.white.withAlpha(8)
            : Colors.white.withAlpha(40),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: Colors.white.withAlpha(isDark ? 15 : 30),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: Colors.white.withAlpha(isDark ? 15 : 30),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: AppTheme.primaryColor.withAlpha(120),
            width: 1.5,
          ),
        ),
        labelStyle: TextStyle(
          color: isDark
              ? Colors.white.withAlpha(100)
              : AppTheme.lightTextSecondary,
        ),
        hintStyle: TextStyle(
          color: isDark
              ? Colors.white.withAlpha(60)
              : AppTheme.lightTextHint,
        ),
      ),
      keyboardType: keyboardType,
      style: TextStyle(
        color: isDark ? Colors.white : AppTheme.lightTextPrimary,
      ),
      onSubmitted: onSubmitted,
    );
  }
}
