import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

/// Drags the current window. A double-tap does not maximize it.
class DesktopDragArea extends StatelessWidget {
  const DesktopDragArea({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (_) {
        windowManager.startDragging();
      },
      child: child,
    );
  }
}
