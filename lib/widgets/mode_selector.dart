import 'package:flutter/material.dart';
import '../models/app_settings.dart';
import '../theme/app_theme.dart';
import 'glass_container.dart';

/// 代理模式选择器 (全局/规则/直连) - 液态玻璃风格
class ModeSelector extends StatelessWidget {
  final ProxyMode currentMode;
  final void Function(ProxyMode mode)? onModeChanged;

  const ModeSelector({
    super.key,
    required this.currentMode,
    this.onModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GlassContainer(
      borderRadius: 14,
      padding: const EdgeInsets.all(4),
      enableShadow: false,
      child: Row(
        children: ProxyMode.values.map((mode) {
          final isSelected = mode == currentMode;
          return Expanded(
            child: GestureDetector(
              onTap: () => onModeChanged?.call(mode),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  gradient: isSelected
                      ? const LinearGradient(
                          colors: [AppTheme.primaryColor, Color(0xFF8B5CF6)],
                        )
                      : null,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: AppTheme.primaryColor.withAlpha(60),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Center(
                  child: Text(
                    mode.chineseName,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? Colors.white
                          : (isDark
                              ? Colors.white.withAlpha(120)
                              : AppTheme.lightTextSecondary),
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
