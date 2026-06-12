import 'package:flutter/material.dart';
import '../models/proxy_group.dart';
import '../models/proxy_node.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_container.dart';
import 'node_card.dart';

/// 代理组选择器 - 显示一个组及其节点列表
class GroupSelector extends StatefulWidget {
  final ProxyGroup group;
  final String? selectedNodeName;
  final void Function(String nodeName)? onSelectNode;
  final void Function(String nodeName)? onTestLatency;
  final bool initiallyExpanded;

  const GroupSelector({
    super.key,
    required this.group,
    this.selectedNodeName,
    this.onSelectNode,
    this.onTestLatency,
    this.initiallyExpanded = false,
  });

  @override
  State<GroupSelector> createState() => _GroupSelectorState();
}

class _GroupSelectorState extends State<GroupSelector> {
  bool _expanded = false;
  String? _testingNode;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
  }

  Color _groupTypeColor() {
    switch (widget.group.type.toLowerCase()) {
      case 'urltest':
      case 'url-test':
        return AppTheme.accentColor;
      case 'fallback':
        return AppTheme.warningColor;
      case 'loadbalance':
      case 'load-balance':
        return AppTheme.successColor;
      default:
        return AppTheme.primaryColor;
    }
  }

  String _groupTypeLabel() {
    switch (widget.group.type.toLowerCase()) {
      case 'urltest':
      case 'url-test':
        return '自动测速';
      case 'fallback':
        return '故障转移';
      case 'loadbalance':
      case 'load-balance':
        return '负载均衡';
      default:
        return '手动选择';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? AppTheme.darkSurface : AppTheme.lightSurface;
    final textColor = isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary;
    final subColor = isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary;

    return GlassContainer(
      borderRadius: 14,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: EdgeInsets.zero,
      enableShadow: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 组头
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  // 类型标签
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _groupTypeColor().withAlpha(25),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: _groupTypeColor().withAlpha(80),
                        width: 0.5,
                      ),
                    ),
                    child: Text(
                      _groupTypeLabel(),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: _groupTypeColor(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),

                  // 组名
                  Expanded(
                    child: Text(
                      widget.group.name,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                    ),
                  ),

                  // 节点数量
                  Text(
                    '${widget.group.nodeCount} 个节点',
                    style: TextStyle(
                      fontSize: 12,
                      color: subColor,
                    ),
                  ),
                  const SizedBox(width: 8),

                  // 展开/折叠图标
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.keyboard_arrow_down,
                      color: subColor,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 节点列表 (展开时)
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Column(
              children: [
                const Divider(height: 1),
                const SizedBox(height: 4),
                ...widget.group.nodes.map((node) => NodeCard(
                  node: node,
                  isSelected: node.name == widget.selectedNodeName,
                  onTap: () => widget.onSelectNode?.call(node.name),
                  onLatencyTest: _testingNode == node.name
                      ? null
                      : () => _handleLatencyTest(node.name),
                  showLatency: true,
                )),
                const SizedBox(height: 8),
              ],
            ),
            crossFadeState: _expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }

  Future<void> _handleLatencyTest(String nodeName) async {
    setState(() => _testingNode = nodeName);
    widget.onTestLatency?.call(nodeName);
    // 延迟后清除测试状态
    Future.delayed(const Duration(seconds: 6), () {
      if (mounted) {
        setState(() => _testingNode = null);
      }
    });
  }
}
