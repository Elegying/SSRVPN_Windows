import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';
import 'app.dart';

const Size _preferredWindowSize = Size(480, 780);
const Size _preferredMinimumSize = Size(420, 680);
const double _windowHorizontalMargin = 24;
const double _windowVerticalMargin = 32;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化 window_manager
  await windowManager.ensureInitialized();
  await windowManager.setPreventClose(true);
  final placement = await _resolveWindowPlacement();

  final windowOptions = WindowOptions(
    size: placement.size,
    minimumSize: placement.minimumSize,
    center: placement.bounds == null,
    backgroundColor: Colors.transparent,
    titleBarStyle: TitleBarStyle.normal,
    title: 'SSRVPN',
    windowButtonVisibility: true,
  );

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    final bounds = placement.bounds;
    if (bounds != null) {
      await windowManager.setBounds(bounds);
    }
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(const SSRVpnApp());
}

Future<_WindowPlacement> _resolveWindowPlacement() async {
  try {
    final display = await screenRetriever.getPrimaryDisplay();
    final visibleSize = display.visibleSize ?? display.size;
    final visiblePosition = display.visiblePosition ?? Offset.zero;

    final maxWidth = visibleSize.width - _windowHorizontalMargin;
    final maxHeight = visibleSize.height - _windowVerticalMargin;
    final width = _fitDimension(_preferredWindowSize.width, maxWidth);
    final height = _fitDimension(_preferredWindowSize.height, maxHeight);
    final size = Size(width, height);
    final minimumSize = Size(
      math.min(_preferredMinimumSize.width, width),
      math.min(_preferredMinimumSize.height, height),
    );
    final left =
        visiblePosition.dx + math.max(0, (visibleSize.width - width) / 2);
    final top =
        visiblePosition.dy + math.max(0, (visibleSize.height - height) / 2);

    return _WindowPlacement(
      size: size,
      minimumSize: minimumSize,
      bounds: Rect.fromLTWH(left, top, width, height),
    );
  } catch (_) {
    return const _WindowPlacement(
      size: _preferredWindowSize,
      minimumSize: _preferredMinimumSize,
    );
  }
}

double _fitDimension(double preferred, double available) {
  if (!available.isFinite || available <= 0) return preferred;
  return math.min(preferred, available);
}

class _WindowPlacement {
  const _WindowPlacement({
    required this.size,
    required this.minimumSize,
    this.bounds,
  });

  final Size size;
  final Size minimumSize;
  final Rect? bounds;
}
