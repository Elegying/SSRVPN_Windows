import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/subscription.dart';
import '../services/subscription_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_container.dart';

/// 订阅管理页面 - 液态玻璃风格
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
          content: Text('请输入订阅链接或SSR链接'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
      return;
    }

    setState(() => _isAdding = true);

    try {
      final subService = context.read<SubscriptionService>();

      if (subService.isSsrLink(url)) {
        // SSR链接作为订阅条目保存，刷新时自动解析
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
        if (parsedUri == null || !parsedUri.hasScheme) {
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

        // 自动刷新订阅
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
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('刷新失败: $e'),
                backgroundColor: AppTheme.errorColor,
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
      setState(() => _isAdding = false);
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

      if (yaml != null && yaml.isNotEmpty) {
        final nodeCount = subService.allNodes.length;
        final groupCount = subService.allGroups.length;
        setState(() {
          _refreshResult = '成功: 获取到 $nodeCount 个节点, $groupCount 个分组';
        });
      } else {
        setState(() => _refreshResult = '刷新失败: 未获取到配置数据');
      }
    } catch (e) {
      setState(() => _refreshResult = '刷新失败: $e');
    } finally {
      setState(() => _isRefreshing = false);
    }
  }

  Future<void> _deleteSubscription(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.transparent,
        contentPadding: EdgeInsets.zero,
        content: GlassContainer(
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
                  color: Colors.white.withAlpha(120),
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
    );

    if (confirmed == true) {
      final subService = context.read<SubscriptionService>();
      await subService.removeSubscription(id);
      setState(() {});
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
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 标题区
              _buildHeader(isDark),
              const SizedBox(height: 24),

              // 添加订阅卡片
              _buildAddCard(isDark),
              const SizedBox(height: 24),

              // 订阅列表
              if (subscriptions.isNotEmpty)
                _buildSubscriptionList(subService, subscriptions, isDark),

              // 空状态
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
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppTheme.primaryColor, AppTheme.accentColor],
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.rss_feed, color: Colors.white, size: 20),
        ),
        const SizedBox(width: 14),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '订阅管理',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : AppTheme.lightTextPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '支持订阅链接与 ssr:// 导入',
              style: TextStyle(
                fontSize: 12,
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
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.add_circle_outline,
                size: 18,
                color: AppTheme.accentColor,
              ),
              const SizedBox(width: 8),
              Text(
                '添加订阅',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : AppTheme.lightTextPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 链接输入框
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
          const SizedBox(height: 14),

          // 添加按钮
          SizedBox(
            width: double.infinity,
            height: 44,
            child: Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppTheme.primaryColor, Color(0xFF8B5CF6)],
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primaryColor.withAlpha(60),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ElevatedButton(
                onPressed: _isAdding ? null : _addSubscription,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isAdding
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        '添加',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
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
        // 列表头部
        Row(
          children: [
            Text(
              '我的订阅',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : AppTheme.lightTextPrimary,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withAlpha(30),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${subscriptions.length}',
                style: const TextStyle(
                  color: AppTheme.primaryColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: _isRefreshing ? null : _refreshAll,
              icon: _isRefreshing
                  ? const SizedBox(
                      width: 14,
                      height: 14,
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
        const SizedBox(height: 8),

        // 刷新结果
        if (_refreshResult != null)
          _buildRefreshResult(isDark),

        // 订阅卡片
        ...subscriptions.map((sub) => _buildSubscriptionCard(sub, isDark)),
      ],
    );
  }

  Widget _buildRefreshResult(bool isDark) {
    final isSuccess = _refreshResult!.startsWith('成功');
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
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
                fontSize: 12,
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
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // 图标
              Container(
                width: 38,
                height: 38,
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
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),

              // 名称和链接
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sub.name,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color:
                            isDark ? Colors.white : AppTheme.lightTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      sub.url,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withAlpha(isDark ? 60 : 100),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),

              // 删除按钮
              IconButton(
                onPressed: () => _deleteSubscription(sub.id),
                icon: Icon(
                  Icons.delete_outline,
                  size: 20,
                  color: AppTheme.errorColor.withAlpha(150),
                ),
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(),
                tooltip: '删除订阅',
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 状态栏
          Row(
            children: [
              _buildStatusDot(
                sub.enabled ? AppTheme.successColor : AppTheme.errorColor,
              ),
              const SizedBox(width: 5),
              Text(
                sub.enabled ? '已启用' : '已禁用',
                style: TextStyle(
                  fontSize: 11,
                  color: sub.enabled
                      ? AppTheme.successColor
                      : AppTheme.errorColor,
                ),
              ),
              const SizedBox(width: 16),
              Icon(
                Icons.access_time,
                size: 13,
                color: Colors.white.withAlpha(isDark ? 60 : 100),
              ),
              const SizedBox(width: 4),
              Text(
                sub.lastUpdate != null
                    ? '更新于 ${_formatDate(sub.lastUpdate!)}'
                    : '未更新',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white.withAlpha(isDark ? 60 : 100),
                ),
              ),
              const Spacer(),
              if (sub.autoUpdate)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.accentColor.withAlpha(20),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: AppTheme.accentColor.withAlpha(40),
                    ),
                  ),
                  child: const Text(
                    '自动更新',
                    style:
                        TextStyle(fontSize: 10, color: AppTheme.accentColor),
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
      width: 6,
      height: 6,
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
        padding: const EdgeInsets.only(top: 60),
        child: Column(
          children: [
            Container(
              width: 80,
              height: 80,
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
                size: 36,
                color: AppTheme.primaryColor.withAlpha(100),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '暂无订阅',
              style: TextStyle(
                fontSize: 16,
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
                fontSize: 12,
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
