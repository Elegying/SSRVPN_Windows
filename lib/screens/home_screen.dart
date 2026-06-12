import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/proxy_node.dart';
import '../models/app_settings.dart';
import '../services/clash_service.dart';
import '../services/subscription_service.dart';
import '../services/settings_service.dart';
import '../services/system_proxy_service.dart';
import '../theme/app_theme.dart';
import '../widgets/connection_button.dart';
import '../widgets/glass_container.dart';

/// 主屏幕 — Premium Design
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<ProxyNode> _nodes = [];
  bool _isConnected = false;
  bool _isConnecting = false;
  String? _errorMessage;
  Timer? _nodeRefreshTimer;
  String? _testingNodeName;
  ProxyNode? _selectedNode;

  final Map<String, int> _latencies = {};
  int _lastKnownNodeCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadInitialData());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final subService = context.read<SubscriptionService>();
    final currentCount = subService.allNodes.length;
    if (currentCount != _lastKnownNodeCount && currentCount > 0) {
      _lastKnownNodeCount = currentCount;
      setState(() => _nodes = List.from(subService.allNodes));
      // 新增节点后自动重载配置，让 AtlasCore 认识新节点
      if (_isConnected) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _reloadConfig());
      }
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
      final config = clashService.generateClashConfig(rawYaml, settingsService.settings);
      await clashService.stop();
      await clashService.writeConfig(config);
      final success = await clashService.start();
      if (mounted) {
        setState(() { _isConnected = success; _isConnecting = false; });
        if (success && settingsService.settings.enableSystemProxy) {
          try {
            await context.read<SystemProxyService>().setSystemProxy('127.0.0.1', settingsService.settings.proxyPort);
          } catch (_) {}
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() { _isConnected = false; _isConnecting = false; });
      }
    }
  }

  @override
  void dispose() {
    _nodeRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    final subService = context.read<SubscriptionService>();
    final clashService = context.read<ClashService>();
    if (subService.allNodes.isNotEmpty) {
      setState(() {
        _nodes = List.from(subService.allNodes);
        _lastKnownNodeCount = subService.allNodes.length;
      });
    }
    if (clashService.isRunning) setState(() => _isConnected = true);
  }

  Future<void> _handleConnectToggle() async {
    if (_isConnecting) return;
    final clashService = context.read<ClashService>();
    final subService = context.read<SubscriptionService>();
    final settingsService = context.read<SettingsService>();

    if (_isConnected) {
      setState(() { _isConnecting = true; _errorMessage = null; });
      await clashService.stop();
      _nodeRefreshTimer?.cancel();
      try { await context.read<SystemProxyService>().clearSystemProxy(); } catch (_) {}
      setState(() { _isConnected = false; _isConnecting = false; _latencies.clear(); });
    } else {
      setState(() { _isConnecting = true; _errorMessage = null; });
      final rawYaml = subService.rawYaml;
      if (rawYaml == null || rawYaml.isEmpty) {
        setState(() { _errorMessage = '请先添加并刷新订阅'; _isConnecting = false; });
        return;
      }
      await settingsService.updateProxyMode(ProxyMode.rule);
      final config = clashService.generateClashConfig(rawYaml, settingsService.settings);
      await clashService.writeConfig(config);
      final success = await clashService.start();
      if (success) {
        setState(() { _isConnected = true; _isConnecting = false; _nodes = List.from(subService.allNodes); });
        if (settingsService.settings.enableSystemProxy) {
          await context.read<SystemProxyService>().setSystemProxy('127.0.0.1', settingsService.settings.proxyPort);
        }
      } else {
        setState(() { _errorMessage = '连接失败: 无法启动VPN核心'; _isConnecting = false; });
      }
    }
  }

  Future<void> _handleTestLatency(String nodeName) async {
    if (!_isConnected || _testingNodeName == nodeName) return;
    setState(() => _testingNodeName = nodeName);
    final clashService = context.read<ClashService>();
    final settings = context.read<SettingsService>().settings;
    final latency = await clashService.testLatency(nodeName, timeout: settings.latencyTestTimeout);
    if (mounted) {
      setState(() {
        _latencies[nodeName] = latency;
        _testingNodeName = null;
        for (final node in _nodes) {
          if (node.name == nodeName) { node.latency = latency; node.lastLatencyTest = DateTime.now(); }
        }
      });
    }
  }

  Future<void> _handleSelectNode(ProxyNode node) async {
    setState(() => _selectedNode = node);
    if (!_isConnected) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请先连接VPN'), duration: Duration(seconds: 1)),
        );
      }
      return;
    }
    final ok = await context.read<ClashService>().switchProxy('PROXY', node.name);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok ? '已切换: ${node.name}' : '切换失败: ${node.name}'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _handleTestAllLatency() async {
    if (!_isConnected) return;
    for (final node in _nodes) {
      await _handleTestLatency(node.name);
      await Future.delayed(const Duration(milliseconds: 300));
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>().settings;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary;
    final subColor = isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary;

    final subService = context.read<SubscriptionService>();
    final currentCount = subService.allNodes.length;
    if (currentCount != _lastKnownNodeCount && currentCount > 0) {
      _lastKnownNodeCount = currentCount;
      _nodes = List.from(subService.allNodes);
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          children: [
            // ── 顶部状态区 ──
            _buildStatusBar(isDark, textColor, subColor, settings),

            // ── 节点列表 ──
            if (!_isConnected)
              _buildHint(isDark),
            Expanded(child: _buildNodeList(textColor, subColor, isDark)),
          ],
        ),
      ),
    );
  }

  Widget _buildHint(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
        decoration: BoxDecoration(
          color: AppTheme.warningColor.withAlpha(isDark ? 12 : 15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppTheme.warningColor.withAlpha(isDark ? 30 : 40),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline_rounded,
                size: 18, color: AppTheme.warningColor.withAlpha(isDark ? 200 : 230)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '请先打开连接开关，然后再切换节点才能生效',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.warningColor.withAlpha(isDark ? 200 : 230),
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBar(bool isDark, Color textColor, Color subColor, AppSettings settings) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      child: GlassContainer(
        borderRadius: 20,
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
        child: Column(
          children: [
            // 连接按钮
            ConnectionButton(
              isConnected: _isConnected,
              isConnecting: _isConnecting,
              onTap: _handleConnectToggle,
            ),
            const SizedBox(height: 20),

            // 状态文字
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Text(
                _isConnecting
                    ? '正在连接...'
                    : _isConnected
                        ? '已连接'
                        : '未连接',
                key: ValueKey(_isConnecting ? 'connecting' : _isConnected ? 'connected' : 'idle'),
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                  color: _isConnected ? AppTheme.successColor : textColor,
                ),
              ),
            ),

            if (_isConnected) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: AppTheme.successColor.withAlpha(15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6, height: 6,
                      decoration: const BoxDecoration(
                        color: AppTheme.successColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'PAC模式 · 端口 ${settings.proxyPort}',
                      style: TextStyle(fontSize: 12, color: subColor, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            ],

            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.errorColor.withAlpha(15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.errorColor.withAlpha(40)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 14, color: AppTheme.errorColor),
                    const SizedBox(width: 8),
                    Text(_errorMessage!, style: const TextStyle(color: AppTheme.errorColor, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildNodeList(Color textColor, Color subColor, bool isDark) {
    return Column(
      children: [
        // ── 标题栏 ──
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 4),
          child: Row(
            children: [
              Container(
                width: 3, height: 16,
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '全部节点',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: textColor, letterSpacing: -0.2),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withAlpha(20),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${_nodes.length}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.primaryColor),
                ),
              ),
              const Spacer(),
              if (_isConnected)
                _SmallButton(
                  icon: Icons.speed,
                  label: '全部测速',
                  onTap: _handleTestAllLatency,
                ),
              const SizedBox(width: 8),
              _SmallButton(
                icon: Icons.refresh_rounded,
                label: '刷新',
                onTap: () {
                  final subService = context.read<SubscriptionService>();
                  setState(() => _nodes = List.from(subService.allNodes));
                },
              ),
            ],
          ),
        ),

        // ── 节点列表 ──
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
              width: 28, height: 28,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: AppTheme.primaryColor),
            ),
            const SizedBox(height: 16),
            Text('正在启动VPN核心...', style: TextStyle(fontSize: 14, color: subColor)),
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
              width: 72, height: 72,
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withAlpha(10),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.dns_outlined, size: 32, color: AppTheme.primaryColor.withAlpha(100)),
            ),
            const SizedBox(height: 20),
            Text('暂无节点', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: textColor)),
            const SizedBox(height: 8),
            Text('请先在订阅页面添加订阅链接', style: TextStyle(fontSize: 13, color: subColor)),
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

        return _NodeCard(
          node: node,
          latency: latency,
          isTesting: isTesting,
          isSelected: isSelected,
          isConnected: _isConnected,
          onTestLatency: () => _handleTestLatency(node.name),
          onTap: () => _handleSelectNode(node),
          textColor: textColor,
          subColor: subColor,
          isDark: isDark,
        );
      },
    );
  }
}

/// 小按钮组件
class _SmallButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SmallButton({required this.icon, required this.label, required this.onTap});

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
          border: Border.all(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: AppTheme.primaryColor),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppTheme.primaryColor)),
          ],
        ),
      ),
    );
  }
}

/// 节点卡片 — Premium 设计
class _NodeCard extends StatelessWidget {
  final ProxyNode node;
  final int? latency;
  final bool isTesting;
  final bool isSelected;
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
    required this.isConnected,
    required this.onTestLatency,
    required this.onTap,
    required this.textColor,
    required this.subColor,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: isSelected
                ? (isDark ? AppTheme.successColor.withAlpha(15) : AppTheme.successColor.withAlpha(10))
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
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                // 选中指示器
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 28, height: 28,
                  decoration: BoxDecoration(
                    color: isSelected ? AppTheme.successColor : (isDark ? AppTheme.darkCard : AppTheme.lightBg),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected ? AppTheme.successColor : (isDark ? AppTheme.darkBorderLight : AppTheme.lightBorder),
                    ),
                  ),
                  child: isSelected
                      ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
                      : Center(
                          child: Text(
                            '${node.name.characters.first}',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.primaryColor),
                          ),
                        ),
                ),
                const SizedBox(width: 12),

                // 节点信息
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        node.name,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                          color: isSelected ? AppTheme.successColor : textColor,
                          letterSpacing: -0.1,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          _TypeBadge(type: node.type),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${node.server}:${node.port}',
                              style: TextStyle(fontSize: 11, color: subColor),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // 延迟显示
                if (isTesting)
                  const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryColor),
                  )
                else if (latency != null && latency! > 0)
                  _LatencyBadge(latency: latency!)
                else if (isConnected)
                  GestureDetector(
                    onTap: onTestLatency,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withAlpha(15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text('测速', style: TextStyle(fontSize: 11, color: AppTheme.primaryColor.withAlpha(200))),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 节点类型标签
class _TypeBadge extends StatelessWidget {
  final String type;
  const _TypeBadge({required this.type});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final typeUpper = type.toUpperCase();
    final display = typeUpper.length > 4 ? typeUpper.substring(0, 4) : typeUpper;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: AppTheme.primaryColor.withAlpha(isDark ? 20 : 15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        display,
        style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: AppTheme.primaryColor, letterSpacing: 0.5),
      ),
    );
  }
}

/// 延迟标签
class _LatencyBadge extends StatelessWidget {
  final int latency;
  const _LatencyBadge({required this.latency});

  @override
  Widget build(BuildContext context) {
    final color = latency < 200 ? AppTheme.successColor : latency < 500 ? AppTheme.warningColor : AppTheme.errorColor;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '${latency}ms',
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}
