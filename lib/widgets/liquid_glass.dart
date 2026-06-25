import 'dart:ui';
import 'package:flutter/material.dart';

const double _bottomNavSurfaceOpacity = 0.02; // 98% transparent.
const double _bottomNavIndicatorOpacity = 0.02; // 98% transparent.

/// 液态玻璃容器 — 模拟 iOS 26 Liquid Glass 效果
/// 支持 Android + macOS，纯 Flutter 实现
class LiquidGlassContainer extends StatelessWidget {
  final Widget child;
  final double blur;
  final double opacity;
  final BorderRadius borderRadius;
  final EdgeInsets padding;
  final double? width;
  final double? height;

  const LiquidGlassContainer({
    super.key,
    required this.child,
    this.blur = 25,
    this.opacity = 0.15,
    this.borderRadius = const BorderRadius.all(Radius.circular(20)),
    this.padding = const EdgeInsets.all(16),
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    double alpha(double value) => value.clamp(0.0, 1.0).toDouble();

    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          width: width,
          height: height,
          padding: padding,
          decoration: BoxDecoration(
            // 多层渐变模拟玻璃折射
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? [
                      Colors.white.withValues(alpha: alpha(opacity * 1.2)),
                      Colors.white.withValues(alpha: alpha(opacity * 0.4)),
                      Colors.white.withValues(alpha: alpha(opacity * 0.8)),
                    ]
                  : [
                      Colors.white.withValues(alpha: alpha(opacity * 2.0)),
                      Colors.white.withValues(alpha: alpha(opacity * 0.6)),
                      Colors.white.withValues(alpha: alpha(opacity * 1.5)),
                    ],
              stops: const [0.0, 0.5, 1.0],
            ),
            borderRadius: borderRadius,
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.15)
                  : Colors.white.withValues(alpha: 0.4),
              width: 0.5,
            ),
            // 柔和阴影增加层次感
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.08),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
              // 内发光效果
              BoxShadow(
                color: Colors.white.withValues(alpha: isDark ? 0.05 : 0.2),
                blurRadius: 2,
                offset: const Offset(0, -1),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

/// 液态玻璃按钮
class LiquidGlassButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double borderRadius;

  const LiquidGlassButton({
    super.key,
    required this.child,
    this.onTap,
    this.borderRadius = 14,
  });

  @override
  State<LiquidGlassButton> createState() => _LiquidGlassButtonState();
}

class _LiquidGlassButtonState extends State<LiquidGlassButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnim;
  late Animation<double> _brightnessAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _brightnessAnim = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) {
        _controller.reverse();
        widget.onTap?.call();
      },
      onTapCancel: () => _controller.reverse(),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnim.value,
            child: ColorFiltered(
              colorFilter: ColorFilter.matrix([
                _brightnessAnim.value,
                0,
                0,
                0,
                0,
                0,
                _brightnessAnim.value,
                0,
                0,
                0,
                0,
                0,
                _brightnessAnim.value,
                0,
                0,
                0,
                0,
                0,
                1,
                0,
              ]),
              child: LiquidGlassContainer(
                borderRadius:
                    BorderRadius.all(Radius.circular(widget.borderRadius)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: widget.child,
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 液态玻璃导航栏
class LiquidGlassNavBar extends StatelessWidget {
  final int currentIndex;
  final List<NavItem> items;
  final ValueChanged<int> onTap;

  const LiquidGlassNavBar({
    super.key,
    required this.currentIndex,
    required this.items,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: LiquidGlassContainer(
        blur: 30,
        opacity: _bottomNavSurfaceOpacity,
        borderRadius: const BorderRadius.all(Radius.circular(32)),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: List.generate(items.length, (index) {
            final item = items[index];
            final isActive = index == currentIndex;

            return GestureDetector(
              onTap: () => onTap(index),
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: isActive
                      ? (isDark
                          ? Colors.white.withValues(
                              alpha: _bottomNavIndicatorOpacity,
                            )
                          : Colors.black.withValues(
                              alpha: _bottomNavIndicatorOpacity,
                            ))
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isActive ? item.activeIcon : item.icon,
                      size: 22,
                      color: isActive
                          ? Theme.of(context).colorScheme.primary
                          : (isDark ? Colors.white54 : Colors.black45),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.label,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight:
                            isActive ? FontWeight.w600 : FontWeight.w400,
                        color: isActive
                            ? Theme.of(context).colorScheme.primary
                            : (isDark ? Colors.white54 : Colors.black45),
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

class NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;

  const NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });
}

/// 用法示例
class LiquidGlassDemo extends StatelessWidget {
  const LiquidGlassDemo({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF0A0A0F)
          : const Color(0xFFF2F2F7),
      body: Stack(
        children: [
          // 背景渐变（模拟壁纸透过效果）
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF667eea).withValues(alpha: 0.3),
                  const Color(0xFF764ba2).withValues(alpha: 0.2),
                  const Color(0xFFf093fb).withValues(alpha: 0.15),
                ],
              ),
            ),
          ),

          // 液态玻璃卡片
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  // 顶部状态卡片
                  const LiquidGlassContainer(
                    padding: EdgeInsets.all(20),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 24,
                          child: Icon(Icons.lock_rounded),
                        ),
                        SizedBox(width: 16),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('SSRVPN',
                                style: TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.w700)),
                            Text('已连接', style: TextStyle(fontSize: 13)),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // 操作按钮
                  LiquidGlassButton(
                    onTap: () {},
                    child: const Text('连接',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
