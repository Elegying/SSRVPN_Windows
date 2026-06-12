import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';

/// 液态玻璃效果容器 — 带流动光效动画
class GlassContainer extends StatefulWidget {
  final Widget child;
  final double borderRadius;
  final double blur;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? width;
  final double? height;
  final bool enableShadow;
  final bool enableRainbowBorder;
  final bool enableFlow; // 是否启用流动光效

  const GlassContainer({
    super.key,
    required this.child,
    this.borderRadius = 16,
    this.blur = 45,
    this.padding,
    this.margin,
    this.width,
    this.height,
    this.enableShadow = true,
    this.enableRainbowBorder = true,
    this.enableFlow = true,
  });

  @override
  State<GlassContainer> createState() => _GlassContainerState();
}

class _GlassContainerState extends State<GlassContainer>
    with SingleTickerProviderStateMixin {
  late AnimationController _animCtrl;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: widget.width,
      height: widget.height,
      margin: widget.margin,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        boxShadow: widget.enableShadow
            ? [
                BoxShadow(
                  color: Colors.black.withAlpha(isDark ? 80 : 40),
                  blurRadius: 40,
                  offset: const Offset(0, 12),
                  spreadRadius: -8,
                ),
                BoxShadow(
                  color: const Color(0xFF7B68EE).withAlpha(isDark ? 20 : 12),
                  blurRadius: 60,
                  spreadRadius: -10,
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: widget.blur, sigmaY: widget.blur),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.borderRadius),
              color: isDark
                  ? Colors.white.withAlpha(10)
                  : Colors.white.withAlpha(30),
            ),
            child: AnimatedBuilder(
              animation: _animCtrl,
              builder: (context, child) {
                return CustomPaint(
                  painter: _FlowGlassPainter(
                    borderRadius: widget.borderRadius,
                    isDark: isDark,
                    showRainbow: widget.enableRainbowBorder,
                    flowValue: widget.enableFlow ? _animCtrl.value : 0.0,
                  ),
                  child: Container(
                    padding: widget.padding,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(widget.borderRadius),
                    ),
                    child: widget.child,
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// 流动液态玻璃画笔
class _FlowGlassPainter extends CustomPainter {
  final double borderRadius;
  final bool isDark;
  final bool showRainbow;
  final double flowValue; // 0.0 ~ 1.0 循环

  _FlowGlassPainter({
    required this.borderRadius,
    required this.isDark,
    required this.showRainbow,
    required this.flowValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Radius.circular(borderRadius),
    );

    // 1. 彩虹折射边框（颜色随时间流动）
    if (showRainbow) {
      _drawFlowRainbowBorder(canvas, size, rrect);
    }

    // 2. 流动高光（从左上滑到右下再循环）
    _drawFlowHighlight(canvas, size, rrect);

    // 3. 顶部+左侧边缘高光
    _drawEdgeHighlights(canvas, size, rrect);

    // 4. 内阴影
    _drawInnerShadow(canvas, size, rrect);

    // 5. 流动光泽点
    _drawFlowSheen(canvas, size, rrect);
  }

  void _drawFlowRainbowBorder(Canvas canvas, Size size, RRect rrect) {
    final borderRect = Rect.fromLTWH(0, 0, size.width, size.height);

    // 彩虹渐变 — 旋转角度随 flowValue 变化
    final angle = flowValue * 2 * pi;
    final cosA = cos(angle);
    final sinA = sin(angle);
    final center = Offset(size.width / 2, size.height / 2);
    final halfW = size.width / 2;
    final halfH = size.height / 2;

    // 旋转后的渐变起点/终点
    final begin = Alignment(
      cosA * (-1.0) - sinA * (-1.0),
      sinA * (-1.0) + cosA * (-1.0),
    );
    final end = Alignment(
      cosA * 1.0 - sinA * 1.0,
      sinA * 1.0 + cosA * 1.0,
    );

    final rainbowPaint = Paint()
      ..shader = LinearGradient(
        begin: begin,
        end: end,
        colors: [
          const Color(0xFF00E5FF).withAlpha(isDark ? 140 : 180),
          const Color(0xFF7B68EE).withAlpha(isDark ? 160 : 200),
          const Color(0xFFFF4081).withAlpha(isDark ? 130 : 170),
          const Color(0xFFFFD740).withAlpha(isDark ? 120 : 160),
          const Color(0xFF00E676).withAlpha(isDark ? 130 : 170),
          const Color(0xFF00E5FF).withAlpha(isDark ? 140 : 180),
        ],
        stops: const [0.0, 0.2, 0.4, 0.6, 0.8, 1.0],
      ).createShader(borderRect);

    final outerPath = Path()..addRRect(rrect);
    final innerRrect = RRect.fromRectAndRadius(
      borderRect.deflate(2.0),
      Radius.circular(borderRadius - 1.0),
    );
    final innerPath = Path()..addRRect(innerRrect);
    final borderPath =
        Path.combine(PathOperation.difference, outerPath, innerPath);
    canvas.drawPath(borderPath, rainbowPaint);

    // 内侧白色高光线（亮度随 flowValue 波动）
    final pulse = (sin(flowValue * 2 * pi) + 1) / 2; // 0~1
    final innerAlpha = isDark ? 30 + 30 * pulse : 60 + 40 * pulse;
    final innerGlowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..shader = LinearGradient(
        begin: begin,
        end: end,
        colors: [
          Colors.white.withAlpha(innerAlpha.toInt()),
          Colors.white.withAlpha((innerAlpha * 0.3).toInt()),
          Colors.white.withAlpha((innerAlpha * 0.8).toInt()),
        ],
      ).createShader(borderRect);

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        borderRect.deflate(2.5),
        Radius.circular(borderRadius - 1.2),
      ),
      innerGlowPaint,
    );
  }

  void _drawFlowHighlight(Canvas canvas, Size size, RRect rrect) {
    canvas.save();
    canvas.clipRRect(rrect);

    // 流动高光：一个从左上到右下的椭圆光斑
    final t = flowValue;
    // 使用 ease-in-out 曲线让光斑在两端有停顿
    final eased = t < 0.5
        ? 2 * t * t
        : 1 - (-2 * t + 2) * (-2 * t + 2) / 2;

    final cx = -size.width * 0.3 + eased * size.width * 1.6;
    final cy = -size.height * 0.3 + eased * size.height * 1.6;
    final radiusX = size.width * 0.45;
    final radiusY = size.height * 0.35;

    final highlightPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.white.withAlpha(isDark ? 35 : 70),
          Colors.white.withAlpha(isDark ? 15 : 35),
          Colors.transparent,
        ],
        stops: const [0.0, 0.4, 1.0],
      ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: radiusX));

    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy), width: radiusX * 2, height: radiusY * 2),
      highlightPaint,
    );

    canvas.restore();
  }

  void _drawEdgeHighlights(Canvas canvas, Size size, RRect rrect) {
    canvas.save();
    canvas.clipRRect(rrect);

    // 顶部高光线（亮度随 flowValue 波动）
    final pulse = (sin(flowValue * 2 * pi + pi / 3) + 1) / 2;
    final topAlpha = isDark ? 15 + 35 * pulse : 40 + 50 * pulse;

    final topPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Colors.white.withAlpha((topAlpha * 0.3).toInt()),
          Colors.white.withAlpha(topAlpha.toInt()),
          Colors.white.withAlpha((topAlpha * 0.3).toInt()),
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, size.width, 3));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, 2.5), topPaint);

    // 左侧高光线
    final leftAlpha = isDark ? 10 + 25 * pulse : 25 + 40 * pulse;
    final leftPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withAlpha(leftAlpha.toInt()),
          Colors.white.withAlpha((leftAlpha * 0.2).toInt()),
        ],
      ).createShader(Rect.fromLTWH(0, 0, 2.5, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, 2, size.height), leftPaint);

    canvas.restore();
  }

  void _drawInnerShadow(Canvas canvas, Size size, RRect rrect) {
    canvas.save();
    canvas.clipRRect(rrect);

    final bottomShadow = Paint()
      ..shader = LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [
          Colors.black.withAlpha(isDark ? 35 : 15),
          Colors.transparent,
        ],
        stops: const [0.0, 0.35],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(
      Rect.fromLTWH(0, size.height * 0.65, size.width, size.height * 0.35),
      bottomShadow,
    );

    final rightShadow = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerRight,
        end: Alignment.centerLeft,
        colors: [
          Colors.black.withAlpha(isDark ? 20 : 8),
          Colors.transparent,
        ],
        stops: const [0.0, 0.25],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(
      Rect.fromLTWH(size.width * 0.75, 0, size.width * 0.25, size.height),
      rightShadow,
    );

    canvas.restore();
  }

  void _drawFlowSheen(Canvas canvas, Size size, RRect rrect) {
    // 光泽点沿椭圆轨迹移动
    final t = flowValue * 2 * pi;
    final cx = size.width * 0.5 + cos(t) * size.width * 0.15;
    final cy = size.height * 0.3 + sin(t) * size.height * 0.1;
    final radius = size.shortestSide * 0.4;

    final sheenPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.white.withAlpha(isDark ? 18 : 35),
          Colors.transparent,
        ],
        stops: const [0.0, 1.0],
      ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: radius));

    canvas.save();
    canvas.clipRRect(rrect);
    canvas.drawCircle(Offset(cx, cy), radius, sheenPaint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _FlowGlassPainter oldDelegate) {
    return oldDelegate.flowValue != flowValue;
  }
}

/// 液态玻璃风格输入框装饰
class GlassInputDecoration extends InputDecoration {
  final bool isDark;

  GlassInputDecoration({
    required this.isDark,
    String? hintText,
    String? labelText,
    Widget? prefixIcon,
  }) : super(
          hintText: hintText,
          labelText: labelText,
          prefixIcon: prefixIcon,
          filled: true,
          fillColor: isDark
              ? Colors.white.withAlpha(10)
              : Colors.white.withAlpha(25),
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
              color: const Color(0xFF7B68EE).withAlpha(150),
              width: 1.5,
            ),
          ),
          hintStyle: TextStyle(
            color: isDark
                ? Colors.white.withAlpha(70)
                : Colors.black.withAlpha(70),
          ),
          labelStyle: TextStyle(
            color: isDark
                ? Colors.white.withAlpha(100)
                : Colors.black.withAlpha(120),
          ),
        );
}
