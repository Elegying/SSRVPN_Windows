import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/proxy_node.dart';
import '../models/app_settings.dart';
import '../services/clash_service.dart';
import '../services/subscription_service.dart';
import '../services/settings_service.dart';
import '../services/update_service.dart';
import '../theme/app_theme.dart';
import '../widgets/connection_button.dart';
import '../widgets/glass_container.dart';

/// 主屏幕 — Windows 桌面优化
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<ProxyNode> _nodes = [];
  bool _isConnected = false;
  bool _isConnecting = false;
  bool _isBatchTesting = false;
  String? _errorMessage;
  String? _testingNodeName;
  ProxyNode? _selectedNode;

  final Map<String, int> _latencies = {};
  int _lastRevision = -1;
  bool _disposed = false;
  ClashService? _clashService;
  Timer? _updateCheckTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadInitialData());
  }

  void _onSubscriptionChanged(SubscriptionService subService) {
    if (subService.revision == _lastRevision) return;
    final isFirstSync = _lastRevision == -1;
    _lastRevision = subService.revision;
    _nodes = List.from(subService.allNodes);
    if (!isFirstSync && _isConnected && _nodes.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _reloadConfig());
    }
  }

  Future<void> _reloadConfig() async {
    final subService = context.read<SubscriptionService>();
    final clashService = context.read<ClashService>();
    final settingsService = context.read<SettingsService>();
    final rawYaml = subService.rawYaml;
    if (rawYaml == null || rawYaml.isEmpty) return;

    setState(() => _isConnecting = true);
    try {
      final nodes = List<ProxyNode>.from(subService.allNodes);
      final preferredNode = _resolveDefaultNode(
        nodes,
        settingsService.settings.lastSelectedNodeName,
      );
      clashService.updateSettings(settingsService.settings);
      final config = clashService.generateClashConfig(
        rawYaml,
        settingsService.settings,
        preferredNodeName: preferredNode?.name,
      );
      await clashService.stop();
      await clashService.writeConfig(config);
      final success = await clashService.start();
      if (success && preferredNode != null) {
        final switched =
            await clashService.switchProxy('PROXY', preferredNode.name);
        if (switched) await _rememberSelectedNode(preferredNode);
      }
      if (mounted && !_disposed) {
        setState(() {
          _isConnected = success;
          _isConnecting = false;
          _nodes = nodes;
          _selectedNode = success ? preferredNode : null;
        });
      }
    } catch (e) {
      if (mounted && !_disposed) {
        setState(() {
          _isConnected = false;
          _isConnecting = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _updateCheckTimer?.cancel();
    _clashService?.removeStatusListener(_handleClashStatusChanged);
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    final subService = context.read<SubscriptionService>();
    final clashService = context.read<ClashService>();
    final settingsService = context.read<SettingsService>();
    _clashService = clashService;
    if (subService.allNodes.isNotEmpty) {
      final nodes = List<ProxyNode>.from(subService.allNodes);
      setState(() {
        _nodes = nodes;
        _lastRevision = subService.revision;
        if (clashService.isRunning) {
          _selectedNode = _resolveDefaultNode(
            nodes,
            settingsService.settings.lastSelectedNodeName,
          );
        }
      });
    }
    if (clashService.isRunning) setState(() => _isConnected = true);

    clashService.addStatusListener(_handleClashStatusChanged);
  }

  void _handleClashStatusChanged() {
    final clashService = _clashService;
    if (clashService == null || !mounted || _disposed) return;
    final running = clashService.isRunning;
    if (_isConnected == running) return;
    setState(() {
      _isConnected = running;
      if (!running) {
        _latencies.clear();
        _selectedNode = null;
      }
    });
  }

  Future<void> _handleConnectToggle() async {
    if (_isConnecting) return;
    final clashService = context.read<ClashService>();
    final subService = context.read<SubscriptionService>();
    final settingsService = context.read<SettingsService>();

    if (_isConnected) {
      setState(() {
        _isConnecting = true;
        _errorMessage = null;
      });
      await clashService.stop();
      if (!mounted) return;
      setState(() {
        _isConnected = false;
        _isConnecting = false;
        _latencies.clear();
      });
    } else {
      setState(() {
        _isConnecting = true;
        _errorMessage = null;
      });
      final rawYaml = subService.rawYaml;
      if (rawYaml == null || rawYaml.isEmpty) {
        setState(() {
          _errorMessage = '请先添加并刷新订阅';
          _isConnecting = false;
        });
        return;
      }
      try {
        clashService.updateSettings(settingsService.settings);
        final nodes = List<ProxyNode>.from(subService.allNodes);
        final autoSelect = _resolveDefaultNode(
          nodes,
          settingsService.settings.lastSelectedNodeName,
        );
        final config = clashService.generateClashConfig(
          rawYaml,
          settingsService.settings,
          preferredNodeName: autoSelect?.name,
        );
        await clashService.writeConfig(config);
        final success = await clashService.start();
        if (!mounted) return;
        if (success) {
          if (autoSelect != null) {
            final switched =
                await clashService.switchProxy('PROXY', autoSelect.name);
            if (switched) await _rememberSelectedNode(autoSelect);
          }
          setState(() {
            _isConnected = true;
            _isConnecting = false;
            _nodes = nodes;
            _selectedNode = autoSelect;
          });
          _autoTestAllNodes();
          _checkUpdateDelayed();
        } else {
          setState(() {
            _errorMessage = '连接失败: 无法启动核心';
            _isConnecting = false;
          });
        }
      } catch (e) {
        if (!mounted) return;
        final msg = e.toString().replaceFirst('Exception: ', '');
        setState(() {
          _errorMessage = '连接失败: $msg';
          _isConnecting = false;
        });
      }
    }
  }

  void _checkUpdateDelayed() {
    _updateCheckTimer?.cancel();
    _updateCheckTimer = Timer(const Duration(seconds: 10), () async {
      if (!mounted || !_isConnected) return;
      try {
        const currentVersion = UpdateService.appVersion;
        final result = await UpdateService.checkForUpdate(currentVersion);
        if (result != null && mounted && _isConnected) {
          final (latestVersion, downloadUrl, changelog) = result;
          UpdateService.showUpdateDialog(
            context,
            latestVersion: latestVersion,
            currentVersion: currentVersion,
            downloadUrl: downloadUrl,
            changelog: changelog,
          );
        }
      } catch (e) {
        debugPrint('[更新] 检查更新异常: $e');
      }
    });
  }

  Future<void> _handleTestLatency(
      String nodeName, String server, int port) async {
    if (!_isConnected || _testingNodeName == nodeName) return;
    setState(() => _testingNodeName = nodeName);
    final clashService = context.read<ClashService>();
    final settings = context.read<SettingsService>().settings;
    final latency = await clashService.testLatency(server, port,
        timeoutMs: settings.latencyTestTimeout);
    if (mounted && !_disposed) {
      setState(() {
        _latencies[nodeName] = latency;
        _testingNodeName = null;
        for (final node in _nodes) {
          if (node.name == nodeName) {
            node.latency = latency;
            node.lastLatencyTest = DateTime.now();
          }
        }
      });
    }
  }

  Future<void> _handleSelectNode(ProxyNode node) async {
    if (!_isConnected) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('请先连接VPN'), duration: Duration(seconds: 1)),
        );
      }
      return;
    }
    final ok =
        await context.read<ClashService>().switchProxy('PROXY', node.name);
    if (ok) {
      await _rememberSelectedNode(node);
      if (mounted) setState(() => _selectedNode = node);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(ok ? '已切换: ${node.name}' : '切换失败: ${node.name}'),
            duration: const Duration(seconds: 1)),
      );
    }
  }

  ProxyNode? _resolveDefaultNode(
    List<ProxyNode> nodes,
    String? rememberedNodeName,
  ) {
    if (nodes.isEmpty) return null;
    if (rememberedNodeName != null && rememberedNodeName.isNotEmpty) {
      for (final node in nodes) {
        if (node.name == rememberedNodeName) return node;
      }
    }
    return nodes.first;
  }

  Future<void> _rememberSelectedNode(ProxyNode node) async {
    final settingsService = context.read<SettingsService>();
    final clashService = context.read<ClashService>();
    final subscriptionService = context.read<SubscriptionService>();
    await settingsService.updateLastSelectedNodeName(node.name);
    final rawYaml = subscriptionService.rawYaml;
    if (rawYaml != null && rawYaml.isNotEmpty) {
      final config = clashService.generateClashConfig(
        rawYaml,
        settingsService.settings,
        preferredNodeName: node.name,
      );
      await clashService.writeConfig(config);
    }
  }

  Future<void> _autoTestAllNodes() async {
    if (!_isConnected || _nodes.isEmpty) return;
    final clashService = context.read<ClashService>();
    final timeout = context.read<SettingsService>().settings.latencyTestTimeout;
    setState(() => _isBatchTesting = true);
    await clashService.testAllLatencies(_nodes, (name, latency) {
      if (mounted && !_disposed) {
        setState(() {
          _latencies[name] = latency;
          for (final node in _nodes) {
            if (node.name == name) {
              node.latency = latency;
              node.lastLatencyTest = DateTime.now();
            }
          }
        });
      }
    }, timeoutMs: timeout);
    if (mounted && !_disposed) {
      setState(() => _isBatchTesting = false);
    }
  }

  Future<void> _handleTestAllLatency() async {
    if (!_isConnected) return;
    final clashService = context.read<ClashService>();
    final timeout = context.read<SettingsService>().settings.latencyTestTimeout;
    setState(() => _isBatchTesting = true);
    await clashService.testAllLatencies(_nodes, (name, latency) {
      if (mounted && !_disposed) {
        setState(() {
          _latencies[name] = latency;
          for (final node in _nodes) {
            if (node.name == name) {
              node.latency = latency;
              node.lastLatencyTest = DateTime.now();
            }
          }
        });
      }
    }, timeoutMs: timeout);
    if (mounted && !_disposed) {
      setState(() => _isBatchTesting = false);
    }
  }

  void _showTutorial(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: isDark ? const Color(0xFF1A1D26) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [
                        AppTheme.primaryColor,
                        AppTheme.accentColor
                      ]),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.menu_book_rounded,
                        color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Text('使用教程',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? AppTheme.darkTextPrimary
                              : AppTheme.lightTextPrimary)),
                ],
              ),
              const SizedBox(height: 20),
              const _TutorialStep(step: '1', text: '点击底部「订阅」标签，进入订阅管理页面'),
              const SizedBox(height: 12),
              const _TutorialStep(step: '2', text: '在输入框中粘贴订阅链接，点击「添加」'),
              const SizedBox(height: 12),
              const _TutorialStep(step: '3', text: '添加成功后点击「全部刷新」，等待节点加载完成'),
              const SizedBox(height: 12),
              const _TutorialStep(step: '4', text: '返回主页，点击连接按钮即可使用'),
              const SizedBox(height: 12),
              const _TutorialStep(
                  step: '5', text: '系统代理模式无需管理员权限，TUN 模式需以管理员身份运行'),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    backgroundColor:
                        AppTheme.primaryColor.withAlpha(isDark ? 25 : 15),
                  ),
                  child: const Text('知道了',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.primaryColor)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showLogs(BuildContext context) {
    final clashService = context.read<ClashService>();
    final logs = clashService.recentLogs;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF0E1018),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: 600,
          height: 500,
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  const Icon(Icons.bug_report,
                      size: 18, color: AppTheme.warningColor),
                  const SizedBox(width: 8),
                  const Text('运行日志',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.darkTextPrimary)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.copy,
                        size: 18, color: AppTheme.darkTextSecondary),
                    onPressed: () async {
                      await Clipboard.setData(
                          ClipboardData(text: clashService.recentLogs));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('日志已复制')));
                      }
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.close,
                        size: 18, color: AppTheme.darkTextSecondary),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const Divider(color: AppTheme.darkBorder),
              Expanded(
                child: SingleChildScrollView(
                  child: SelectableText(
                    logs.isEmpty ? '暂无日志' : logs,
                    style: const TextStyle(
                        fontSize: 12,
                        fontFamily: 'Consolas',
                        color: AppTheme.darkTextSecondary,
                        height: 1.6),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>().settings;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor =
        isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary;
    final subColor =
        isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary;

    final subService = context.watch<SubscriptionService>();
    _onSubscriptionChanged(subService);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(isDark, textColor),
            _buildStatusBar(isDark, textColor, subColor, settings),
            Expanded(child: _buildNodeList(textColor, subColor, isDark)),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(bool isDark, Color textColor) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [AppTheme.primaryColor, AppTheme.accentColor]),
              borderRadius: BorderRadius.circular(10),
            ),
            child:
                const Icon(Icons.shield_rounded, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Text('SSRVPN',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: textColor,
                  letterSpacing: 0.5)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withAlpha(20),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text('Windows',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.primaryColor)),
          ),
          const Spacer(),
          if (_isConnected)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppTheme.successColor.withAlpha(20),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle,
                      size: 14, color: AppTheme.successColor),
                  SizedBox(width: 4),
                  Text('已连接',
                      style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.successColor,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => _showTutorial(context),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: isDark ? AppTheme.darkCard : AppTheme.lightBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.menu_book_rounded,
                      size: 14,
                      color: isDark
                          ? AppTheme.darkTextSecondary
                          : AppTheme.lightTextSecondary),
                  const SizedBox(width: 4),
                  Text('使用教程',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: isDark
                              ? AppTheme.darkTextSecondary
                              : AppTheme.lightTextSecondary)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBar(
      bool isDark, Color textColor, Color subColor, AppSettings settings) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
      child: GlassContainer(
        borderRadius: 18,
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
        child: Column(
          children: [
            Row(
              children: [
                ConnectionButton(
                  isConnected: _isConnected,
                  isConnecting: _isConnecting,
                  onTap: _handleConnectToggle,
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: Text(
                          _isConnecting
                              ? '正在连接...'
                              : _isConnected
                                  ? '已连接'
                                  : '未连接',
                          key: ValueKey(_isConnecting
                              ? 'c'
                              : _isConnected
                                  ? 'y'
                                  : 'n'),
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: _isConnected
                                ? AppTheme.successColor
                                : textColor,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      if (_isConnected)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppTheme.successColor.withAlpha(15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${settings.proxyMode.chineseName} · 端口 ${settings.proxyPort}${settings.enableTun ? " · TUN" : " · 代理"}',
                            style: TextStyle(
                                fontSize: 12,
                                color: subColor,
                                fontWeight: FontWeight.w500),
                          ),
                        ),
                      if (_errorMessage != null) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppTheme.errorColor.withAlpha(15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: AppTheme.errorColor.withAlpha(40)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.error_outline,
                                      size: 14, color: AppTheme.errorColor),
                                  const SizedBox(width: 6),
                                  Expanded(
                                      child: Text(_errorMessage!,
                                          style: const TextStyle(
                                              color: AppTheme.errorColor,
                                              fontSize: 12))),
                                ],
                              ),
                              const SizedBox(height: 6),
                              GestureDetector(
                                onTap: () => _showLogs(context),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.bug_report,
                                        size: 12, color: AppTheme.warningColor),
                                    const SizedBox(width: 4),
                                    Text('查看日志',
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: AppTheme.warningColor
                                                .withAlpha(200),
                                            decoration:
                                                TextDecoration.underline)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildModeInfo(isDark, subColor, settings),
          ],
        ),
      ),
    );
  }

  Widget _buildModeInfo(bool isDark, Color subColor, AppSettings settings) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withAlpha(5) : Colors.black.withAlpha(5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppTheme.accentColor.withAlpha(25),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              settings.enableTun
                  ? Icons.wifi_tethering_rounded
                  : Icons.language_rounded,
              size: 18,
              color: AppTheme.accentColor,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  settings.enableTun ? 'TUN 模式' : '系统代理模式',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? AppTheme.darkTextPrimary
                        : AppTheme.lightTextPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  settings.enableTun
                      ? '虚拟网卡代理所有流量（需管理员权限）'
                      : '通过系统代理设置转发流量（无需管理员）',
                  style: TextStyle(fontSize: 12, color: subColor),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNodeList(Color textColor, Color subColor, bool isDark) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
          child: Row(
            children: [
              Container(
                  width: 4,
                  height: 18,
                  decoration: BoxDecoration(
                      color: AppTheme.primaryColor,
                      borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 8),
              Text('全部节点',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: textColor)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withAlpha(20),
                    borderRadius: BorderRadius.circular(8)),
                child: Text('${_nodes.length}',
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primaryColor)),
              ),
              const Spacer(),
              if (_isBatchTesting)
                const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppTheme.primaryColor))
              else if (_isConnected)
                _SmallButton(
                    icon: Icons.speed,
                    label: '测速',
                    onTap: _handleTestAllLatency),
            ],
          ),
        ),
        Expanded(child: _buildNodeListView(textColor, subColor, isDark)),
      ],
    );
  }

  Widget _buildNodeListView(Color textColor, Color subColor, bool isDark) {
    if (_isConnecting) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(
                    strokeWidth: 2.5, color: AppTheme.primaryColor)),
            const SizedBox(height: 16),
            Text('正在启动核心...', style: TextStyle(fontSize: 14, color: subColor)),
          ],
        ),
      );
    }

    if (_nodes.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withAlpha(10),
                  shape: BoxShape.circle),
              child: Icon(Icons.dns_outlined,
                  size: 32, color: AppTheme.primaryColor.withAlpha(100)),
            ),
            const SizedBox(height: 20),
            Text('暂无节点',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: textColor)),
            const SizedBox(height: 8),
            Text('请先在订阅页面添加订阅链接',
                style: TextStyle(fontSize: 13, color: subColor)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      itemCount: _nodes.length,
      itemBuilder: (context, index) {
        final node = _nodes[index];
        final latency = _latencies[node.name] ?? node.latency;
        final isTesting = _testingNodeName == node.name;
        final isSelected = _selectedNode?.name == node.name;
        final isTimeout = latency != null && (latency <= 0 || latency >= 65535);

        return _NodeCard(
          node: node,
          latency: latency,
          isTesting: isTesting,
          isSelected: isSelected,
          isTimeout: isTimeout,
          isConnected: _isConnected,
          onTestLatency: () =>
              _handleTestLatency(node.name, node.server, node.port),
          onTap: () => _handleSelectNode(node),
          textColor: textColor,
          subColor: subColor,
          isDark: isDark,
        );
      },
    );
  }
}

class _SmallButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _SmallButton(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkCard : AppTheme.lightBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: AppTheme.primaryColor),
            const SizedBox(width: 4),
            Text(label,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.primaryColor)),
          ],
        ),
      ),
    );
  }
}

class _NodeCard extends StatelessWidget {
  final ProxyNode node;
  final int? latency;
  final bool isTesting;
  final bool isSelected;
  final bool isTimeout;
  final bool isConnected;
  final VoidCallback onTestLatency;
  final VoidCallback onTap;
  final Color textColor;
  final Color subColor;
  final bool isDark;

  const _NodeCard({
    required this.node,
    required this.latency,
    required this.isTesting,
    required this.isSelected,
    required this.isTimeout,
    required this.isConnected,
    required this.onTestLatency,
    required this.onTap,
    required this.textColor,
    required this.subColor,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveTextColor = isTimeout ? textColor.withAlpha(80) : textColor;
    final effectiveSubColor = isTimeout ? subColor.withAlpha(60) : subColor;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: GestureDetector(
        onTap: isTimeout ? null : onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: isSelected
                ? (isDark
                    ? AppTheme.successColor.withAlpha(15)
                    : AppTheme.successColor.withAlpha(10))
                : null,
            border: Border.all(
              color: isSelected
                  ? AppTheme.successColor.withAlpha(80)
                  : isDark
                      ? AppTheme.darkBorder
                      : AppTheme.lightBorder,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Opacity(
            opacity: isTimeout ? 0.45 : 1.0,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppTheme.successColor
                          : (isDark ? AppTheme.darkCard : AppTheme.lightBg),
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: isSelected
                              ? AppTheme.successColor
                              : (isDark
                                  ? AppTheme.darkBorderLight
                                  : AppTheme.lightBorder)),
                    ),
                    child: isSelected
                        ? const Icon(Icons.check_rounded,
                            size: 18, color: Colors.white)
                        : isTimeout
                            ? Icon(Icons.close_rounded,
                                size: 16,
                                color: AppTheme.errorColor.withAlpha(150))
                            : Center(
                                child: Text(node.name.characters.first,
                                    style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: AppTheme.primaryColor))),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(node.name,
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: isSelected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: isSelected
                                    ? AppTheme.successColor
                                    : effectiveTextColor),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 3),
                        Row(children: [
                          _TypeBadge(type: node.type, isTimeout: isTimeout),
                          const SizedBox(width: 8),
                          Expanded(
                              child: Text('${node.server}:${node.port}',
                                  style: TextStyle(
                                      fontSize: 11, color: effectiveSubColor),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis)),
                        ]),
                      ],
                    ),
                  ),
                  if (isTesting)
                    const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppTheme.primaryColor))
                  else if (isTimeout)
                    const _LatencyBadge(latency: 65535)
                  else if (latency != null && latency! > 0)
                    _LatencyBadge(latency: latency!)
                  else if (isConnected)
                    GestureDetector(
                      onTap: onTestLatency,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                            color: AppTheme.primaryColor.withAlpha(15),
                            borderRadius: BorderRadius.circular(6)),
                        child: Text('测速',
                            style: TextStyle(
                                fontSize: 11,
                                color: AppTheme.primaryColor.withAlpha(200))),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TypeBadge extends StatelessWidget {
  final String type;
  final bool isTimeout;
  const _TypeBadge({required this.type, this.isTimeout = false});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final display = type.toUpperCase().length > 4
        ? type.toUpperCase().substring(0, 4)
        : type.toUpperCase();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
          color: AppTheme.primaryColor
              .withAlpha(isTimeout ? 8 : (isDark ? 20 : 15)),
          borderRadius: BorderRadius.circular(4)),
      child: Text(display,
          style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: AppTheme.primaryColor.withAlpha(isTimeout ? 100 : 255),
              letterSpacing: 0.5)),
    );
  }
}

class _LatencyBadge extends StatelessWidget {
  final int latency;
  const _LatencyBadge({required this.latency});

  bool get isTimeout => latency <= 0 || latency >= 65535;

  @override
  Widget build(BuildContext context) {
    final color = isTimeout
        ? AppTheme.errorColor
        : latency < 200
            ? AppTheme.successColor
            : latency < 500
                ? AppTheme.warningColor
                : AppTheme.errorColor;
    final text = isTimeout ? '超时' : '${latency}ms';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
          color: color.withAlpha(15), borderRadius: BorderRadius.circular(6)),
      child: Text(text,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w600, color: color)),
    );
  }
}

class _TutorialStep extends StatelessWidget {
  final String step;
  final String text;
  const _TutorialStep({required this.step, required this.text});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: AppTheme.primaryColor.withAlpha(isDark ? 30 : 20),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(step,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primaryColor)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              text,
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: isDark
                    ? AppTheme.darkTextPrimary
                    : AppTheme.lightTextPrimary,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
