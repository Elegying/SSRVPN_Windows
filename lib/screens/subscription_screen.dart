import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/subscription.dart';
import '../services/clash_service.dart';
import '../services/subscription_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_container.dart';

/// 订阅管理页面 - Windows 桌面优化
class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  final _urlController = TextEditingController();
  bool _isAdding = false;
  bool _isRefreshing = false;
  String? _refreshResult;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _addSubscription() async {
    final url = _urlController.text.trim();

    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('请输入订阅链接或SSR链接'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
      return;
    }

    setState(() => _isAdding = true);

    try {
      final subService = context.read<SubscriptionService>();

      if (subService.subscriptions.any((s) => s.url == url)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('该订阅已存在，无需重复添加'),
            backgroundColor: AppTheme.warningColor,
          ),
        );
        return;
      }

      if (subService.isSsrLink(url)) {
        await subService.addSubscription('SSR节点', url);
        _urlController.clear();

        try {
          final yaml = await subService.refreshAllSubscriptions();
          if (mounted) {
            if (yaml != null && yaml.isNotEmpty) {
              final nodeCount = subService.allNodes.length;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('SSR链接已导入，当前共 $nodeCount 个节点'),
                  backgroundColor: AppTheme.successColor,
                ),
              );
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('SSR链接已添加，但未获取到数据'),
                  backgroundColor: AppTheme.warningColor,
                ),
              );
            }
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('导入失败: $e'),
                backgroundColor: AppTheme.errorColor,
              ),
            );
          }
        }
      } else {
        final parsedUri = Uri.tryParse(url);
        if (parsedUri == null ||
            !parsedUri.hasAuthority ||
            (parsedUri.scheme != 'http' && parsedUri.scheme != 'https')) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('请输入有效的URL地址'),
                backgroundColor: AppTheme.errorColor,
              ),
            );
          }
          return;
        }

        await subService.addSubscription('SSRVPN.VIP', url);
        _urlController.clear();

        try {
          final yaml = await subService.refreshAllSubscriptions();
          if (mounted) {
            if (yaml != null && yaml.isNotEmpty) {
              final nodeCount = subService.allNodes.length;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('订阅成功，获取到 $nodeCount 个节点'),
                  backgroundColor: AppTheme.successColor,
                ),
              );
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('订阅已添加，但未获取到数据'),
                  backgroundColor: AppTheme.warningColor,
                ),
              );
            }
          }
        } catch (e) {
          if (mounted) {
            final msg = e.toString().replaceFirst('Exception: ', '');
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('刷新失败: $msg'),
                backgroundColor: AppTheme.errorColor,
                duration: const Duration(seconds: 4),
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('添加失败: $e'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isAdding = false);
    }
  }

  Future<void> _refreshAll() async {
    setState(() {
      _isRefreshing = true;
      _refreshResult = null;
    });

    try {
      final subService = context.read<SubscriptionService>();
      final yaml = await subService.refreshAllSubscriptions();
      if (!mounted) return;

      if (yaml != null && yaml.isNotEmpty) {
        final nodeCount = subService.allNodes.length;
        final groupCount = subService.allGroups.length;
        setState(() {
          _refreshResult = '成功: 获取到 $nodeCount 个节点, $groupCount 个分组';
        });
      } else {
        setState(() => _refreshResult = '刷新失败: 没有可用的订阅');
      }
    } on SocketException catch (e) {
      if (!mounted) return;
      setState(() => _refreshResult = '刷新失败: 网络连接异常');
      _showNetworkErrorDialog(e.message);
    } on TimeoutException catch (_) {
      if (!mounted) return;
      setState(() => _refreshResult = '刷新失败: 连接超时');
      _showNetworkErrorDialog('连接超时，请检查网络');
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceFirst('Exception: ', '');
      setState(() => _refreshResult = '刷新失败: $msg');
      if (msg.contains('网络') ||
          msg.contains('连接') ||
          msg.contains('Socket') ||
          msg.contains('超时') ||
          msg.contains('DNS')) {
        _showNetworkErrorDialog(msg);
      }
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  void _showNetworkErrorDialog(String detail) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return Dialog(
          backgroundColor: isDark ? const Color(0xFF1A1D26) : Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.88),
            child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppTheme.warningColor.withAlpha(20),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.wifi_off_rounded,
                      size: 28, color: AppTheme.warningColor),
                ),
                const SizedBox(height: 16),
                Text(
                  '网络连接异常',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? AppTheme.darkTextPrimary
                        : AppTheme.lightTextPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '请检查网络连接后重试',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark
                        ? AppTheme.darkTextSecondary
                        : AppTheme.lightTextSecondary,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.errorColor.withAlpha(10),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    detail,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.errorColor.withAlpha(180)),
                  ),
                ),
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
      },
    );
  }

  Future<void> _deleteSubscription(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.transparent,
        contentPadding: EdgeInsets.zero,
        content: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.88),
            child: GlassContainer(
          borderRadius: 20,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                size: 48,
                color: AppTheme.warningColor,
              ),
              const SizedBox(height: 16),
              const Text(
                '确认删除',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                '删除后将无法恢复',
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white.withAlpha(120)
                      : AppTheme.lightTextSecondary,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.errorColor,
                      ),
                      child: const Text('删除'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        ),
      ),
    );

    if (confirmed == true) {
      if (!mounted) return;
      final subService = context.read<SubscriptionService>();
      final clashService = context.read<ClashService>();
      try {
        await subService.removeSubscription(id);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('订阅已删除，但刷新剩余订阅失败，请稍后重试'),
              backgroundColor: AppTheme.warningColor,
            ),
          );
        }
      }
      if (subService.allNodes.isEmpty && clashService.isRunning) {
        await clashService.stop();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
        content: Text('订阅已删除，VPN 已断开'),
              backgroundColor: AppTheme.warningColor,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final subService = context.watch<SubscriptionService>();
    final subscriptions = subService.subscriptions;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(isDark),
              const SizedBox(height: 24),
              _buildAddCard(isDark),
              const SizedBox(height: 28),
              if (subscriptions.isNotEmpty)
                _buildSubscriptionList(subService, subscriptions, isDark),
              if (subscriptions.isEmpty) _buildEmptyState(isDark),
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
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppTheme.primaryColor, AppTheme.accentColor],
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.rss_feed, color: Colors.white, size: 22),
        ),
        const SizedBox(width: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '订阅管理',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : AppTheme.lightTextPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '支持订阅链接与 ssr:// 导入',
              style: TextStyle(
                fontSize: 13,
                color: isDark
                    ? Colors.white.withAlpha(100)
                    : AppTheme.lightTextSecondary,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAddCard(bool isDark) {
    return GlassContainer(
      borderRadius: 18,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.add_circle_outline,
                size: 20,
                color: AppTheme.accentColor,
              ),
              const SizedBox(width: 8),
              Text(
                '添加订阅',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : AppTheme.lightTextPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _urlController,
            decoration: GlassInputDecoration(
              isDark: isDark,
              hintText: '粘贴订阅链接或 ssr:// 链接',
              prefixIcon: const Icon(Icons.link, size: 20),
            ),
            keyboardType: TextInputType.url,
            onSubmitted: (_) => _addSubscription(),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _isAdding ? null : _addSubscription,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                disabledBackgroundColor: AppTheme.primaryColor.withAlpha(100),
                foregroundColor: Colors.white,
                shadowColor: AppTheme.primaryColor.withAlpha(60),
                elevation: 4,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                textStyle:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              child: _isAdding
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('添加'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubscriptionList(
    SubscriptionService subService,
    List<Subscription> subscriptions,
    bool isDark,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '我的订阅',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : AppTheme.lightTextPrimary,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withAlpha(30),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${subscriptions.length}',
                style: const TextStyle(
                  color: AppTheme.primaryColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: _isRefreshing ? null : _refreshAll,
              icon: _isRefreshing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.primaryColor,
                      ),
                    )
                  : const Icon(Icons.refresh, size: 18),
              label: Text(_isRefreshing ? '刷新中...' : '全部刷新'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_refreshResult != null) _buildRefreshResult(isDark),
        ...subscriptions.map((sub) => _buildSubscriptionCard(sub, isDark)),
      ],
    );
  }

  Widget _buildRefreshResult(bool isDark) {
    final isSuccess = _refreshResult!.startsWith('成功');
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isSuccess
            ? AppTheme.successColor.withAlpha(isDark ? 15 : 20)
            : AppTheme.errorColor.withAlpha(isDark ? 15 : 20),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSuccess
              ? AppTheme.successColor.withAlpha(40)
              : AppTheme.errorColor.withAlpha(40),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isSuccess ? Icons.check_circle : Icons.error_outline,
            color: isSuccess ? AppTheme.successColor : AppTheme.errorColor,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _refreshResult!,
              style: TextStyle(
                fontSize: 13,
                color: isSuccess ? AppTheme.successColor : AppTheme.errorColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubscriptionCard(Subscription sub, bool isDark) {
    return GlassContainer(
      borderRadius: 14,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.primaryColor.withAlpha(40),
                      AppTheme.accentColor.withAlpha(40),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.rss_feed,
                  color: AppTheme.primaryColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sub.name,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color:
                            isDark ? Colors.white : AppTheme.lightTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      sub.url,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? Colors.white.withAlpha(60)
                            : AppTheme.lightTextHint,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => _deleteSubscription(sub.id),
                icon: Icon(
                  Icons.delete_outline,
                  size: 22,
                  color: AppTheme.errorColor.withAlpha(150),
                ),
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(),
                tooltip: '删除订阅',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildStatusDot(
                sub.enabled ? AppTheme.successColor : AppTheme.errorColor,
              ),
              const SizedBox(width: 6),
              Text(
                sub.enabled ? '已启用' : '已禁用',
                style: TextStyle(
                  fontSize: 12,
                  color:
                      sub.enabled ? AppTheme.successColor : AppTheme.errorColor,
                ),
              ),
              const SizedBox(width: 16),
              Icon(
                Icons.access_time,
                size: 14,
                color: isDark
                    ? Colors.white.withAlpha(60)
                    : AppTheme.lightTextHint,
              ),
              const SizedBox(width: 4),
              Text(
                sub.lastUpdate != null
                    ? '更新于 ${_formatDate(sub.lastUpdate!)}'
                    : '未更新',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark
                      ? Colors.white.withAlpha(60)
                      : AppTheme.lightTextHint,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusDot(Color color) {
    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: color.withAlpha(100), blurRadius: 4),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(top: 80),
        child: Column(
          children: [
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppTheme.primaryColor.withAlpha(20),
                    AppTheme.accentColor.withAlpha(20),
                  ],
                ),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.rss_feed,
                size: 40,
                color: AppTheme.primaryColor.withAlpha(100),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              '暂无订阅',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: isDark
                    ? Colors.white.withAlpha(120)
                    : AppTheme.lightTextSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '在上方粘贴订阅链接开始使用',
              style: TextStyle(
                fontSize: 13,
                color: isDark
                    ? Colors.white.withAlpha(60)
                    : AppTheme.lightTextHint,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    if (diff.inDays < 7) return '${diff.inDays}天前';
    return '${date.month}/${date.day} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }
}
