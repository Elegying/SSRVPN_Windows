import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/clash_service.dart';
import '../services/settings_service.dart';
import 'package:ssrvpn_shared/services/unlock_test_service.dart';
import '../theme/app_theme.dart';

class UnlockTestScreen extends StatefulWidget {
  const UnlockTestScreen({super.key});

  @override
  State<UnlockTestScreen> createState() => _UnlockTestScreenState();
}

class _UnlockTestScreenState extends State<UnlockTestScreen> {
  final UnlockTestService _service = UnlockTestService();
  List<UnlockTestResult> _items = List.of(UnlockTestService.defaultItems);
  bool _isTestingAll = false;
  final Set<String> _testingIds = {};

  Future<void> _testAll() async {
    if (_isTestingAll) return;
    final clashService = context.read<ClashService>();
    if (!_ensureConnected(clashService)) return;

    setState(() {
      _isTestingAll = true;
      _testingIds
        ..clear()
        ..addAll(_items.map((item) => item.id));
      _items = _items
          .map(
            (item) => item.copyWith(status: 'Testing', clearDetail: true),
          )
          .toList();
    });

    final proxyPort = clashService.runtimeProxyPort;
    final results = await _service.checkAll(proxyPort: proxyPort);
    if (!mounted) return;
    setState(() {
      _items = _mergeResults(_items, results);
      _testingIds.clear();
      _isTestingAll = false;
    });
  }

  Future<void> _testOne(UnlockTestResult item) async {
    if (_testingIds.contains(item.id)) return;
    final clashService = context.read<ClashService>();
    if (!_ensureConnected(clashService)) return;

    setState(() {
      _testingIds.add(item.id);
      _items = _items
          .map(
            (entry) => entry.id == item.id
                ? entry.copyWith(status: 'Testing', clearDetail: true)
                : entry,
          )
          .toList();
    });

    final result = await _service.checkOne(
      id: item.id,
      proxyPort: clashService.runtimeProxyPort,
    );
    if (!mounted) return;
    setState(() {
      _items = _mergeResults(_items, [result]);
      _testingIds.remove(item.id);
    });
  }

  bool _ensureConnected(ClashService clashService) {
    if (clashService.isRunning) return true;
    ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.fromLTRB(16, 0, 16, 16),
        content: Text('请先连接 VPN 后再进行解锁测试')),
    );
    return false;
  }

  List<UnlockTestResult> _mergeResults(
    List<UnlockTestResult> current,
    List<UnlockTestResult> results,
  ) {
    final byId = {for (final result in results) result.id: result};
    return current.map((item) => byId[item.id] ?? item).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor =
        isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary;
    final subColor =
        isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary;
    final clashService = context.read<ClashService>();
    final settings = context.watch<SettingsService>().settings;
    final proxyPort = clashService.isRunning
        ? clashService.runtimeProxyPort
        : settings.proxyPort;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 10),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppTheme.primaryColor, AppTheme.accentColor],
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.fact_check_rounded,
                      color: Colors.white,
                      size: 19,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '解锁测试',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: textColor,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '使用当前节点出口检测流媒体和 AI 服务可用性',
                          style: TextStyle(fontSize: 12, color: subColor),
                        ),
                      ],
                    ),
                  ),
                  _HeaderActionButton(
                    icon: _isTestingAll
                        ? Icons.hourglass_top_rounded
                        : Icons.playlist_play_rounded,
                    label: _isTestingAll ? '测试中' : '全部测试',
                    enabled: !_isTestingAll,
                    onTap: _testAll,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
              child: _InfoStrip(
                isDark: isDark,
                connected: clashService.isRunning,
                proxyPort: proxyPort,
              ),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 22),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 285,
                  mainAxisExtent: 126,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: _items.length,
                itemBuilder: (context, index) {
                  final item = _items[index];
                  return _UnlockCard(
                    item: item,
                    isTesting: _testingIds.contains(item.id),
                    isDark: isDark,
                    textColor: textColor,
                    subColor: subColor,
                    onTest: () => _testOne(item),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoStrip extends StatelessWidget {
  final bool isDark;
  final bool connected;
  final int proxyPort;

  const _InfoStrip({
    required this.isDark,
    required this.connected,
    required this.proxyPort,
  });

  @override
  Widget build(BuildContext context) {
    final color = connected ? AppTheme.successColor : AppTheme.warningColor;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: (isDark ? 16 : 20) / 255),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: (isDark ? 42 : 52) / 255)),
      ),
      child: Row(
        children: [
          Icon(
            connected ? Icons.check_circle_outline_rounded : Icons.info_outline,
            color: color,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              connected
                  ? '当前会显式走 127.0.0.1:$proxyPort 代理端口，测试结果对应当前选中的节点。'
                  : '请先在主页连接 VPN；未连接时测试请求不会发出。',
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                color: color.withValues(alpha: 230 / 255),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UnlockCard extends StatelessWidget {
  final UnlockTestResult item;
  final bool isTesting;
  final bool isDark;
  final Color textColor;
  final Color subColor;
  final VoidCallback onTest;

  const _UnlockCard({
    required this.item,
    required this.isTesting,
    required this.isDark,
    required this.textColor,
    required this.subColor,
    required this.onTest,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(item);
    final checkedText =
        item.checkedAt == null ? '尚未测试' : _formatTime(item.checkedAt!);
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 6 / 255) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: statusColor.withValues(alpha: (item.isPending ? 38 : 90) / 255),
          width: item.isPending ? 1 : 1.2,
        ),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: Colors.black.withValues(alpha: 10 / 255),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 18 / 255),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(_statusIcon(item), size: 17, color: statusColor),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: textColor,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: isTesting ? null : onTest,
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withValues(alpha: 18 / 255),
                      shape: BoxShape.circle,
                    ),
                    child: isTesting
                        ? const Padding(
                            padding: EdgeInsets.all(8),
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppTheme.primaryColor,
                            ),
                          )
                        : const Icon(
                            Icons.refresh_rounded,
                            size: 17,
                            color: AppTheme.primaryColor,
                          ),
                  ),
                ),
              ],
            ),
            const Spacer(),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _Pill(
                  label: _statusLabel(item.status),
                  color: statusColor,
                  isDark: isDark,
                ),
                if (item.region != null)
                  _Pill(
                    label: item.region!,
                    color: AppTheme.primaryColor,
                    isDark: isDark,
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              item.detail ?? checkedText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: subColor),
            ),
          ],
        ),
      ),
    );
  }

  Color _statusColor(UnlockTestResult item) {
    if (isTesting || item.status == 'Testing') return AppTheme.primaryColor;
    if (item.isUnlocked) return AppTheme.successColor;
    if (item.isBlocked) return AppTheme.errorColor;
    if (item.isFailed) return AppTheme.errorColor;
    if (item.status == 'Originals Only') return AppTheme.warningColor;
    if (item.isPending) return subColor;
    return AppTheme.warningColor;
  }

  IconData _statusIcon(UnlockTestResult item) {
    if (isTesting || item.status == 'Testing') {
      return Icons.hourglass_top_rounded;
    }
    if (item.isUnlocked) return Icons.check_circle_rounded;
    if (item.isBlocked) return Icons.cancel_rounded;
    if (item.isFailed) return Icons.help_rounded;
    if (item.status == 'Originals Only') return Icons.warning_rounded;
    return Icons.pending_rounded;
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'Pending':
        return '待测试';
      case 'Testing':
        return '测试中';
      case 'Yes':
        return '支持';
      case 'No':
        return '不支持';
      case 'Failed':
        return '失败';
      case 'Originals Only':
        return '仅自制剧';
      case 'Unsupported Country/Region':
        return '地区不支持';
      case 'Disallowed ISP':
        return 'ISP 受限';
      case 'Blocked':
        return '被阻止';
      default:
        if (status.startsWith('Failed')) return '失败';
        if (status.startsWith('No')) return '不支持';
        return status;
    }
  }

  String _formatTime(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '测试时间 $hour:$minute';
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final Color color;
  final bool isDark;

  const _Pill({
    required this.label,
    required this.color,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: (isDark ? 24 : 18) / 255),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _HeaderActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  const _HeaderActionButton({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.65,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppTheme.primaryColor.withValues(alpha: 20 / 255),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 55 / 255)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: AppTheme.primaryColor),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.primaryColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
