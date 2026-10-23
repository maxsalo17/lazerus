import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'color_utils.dart';

enum HoldValueKind { hue, brightness }

/// Opens a control-relative overlay as soon as a long press is recognized.
/// Horizontal motion behaves like a wheel: it is measured from the value that
/// was active when the finger went down; vertical motion has no effect.
class HoldValueControl extends StatefulWidget {
  const HoldValueControl({
    super.key,
    required this.kind,
    required this.value,
    required this.label,
    required this.onPreview,
    required this.onCommit,
    this.brightnessColor = Colors.red,
    this.enabled = true,
  });

  final HoldValueKind kind;
  final double value;
  final String label;
  final ValueChanged<double> onPreview;
  final ValueChanged<double> onCommit;
  final Color brightnessColor;
  final bool enabled;

  @override
  State<HoldValueControl> createState() => _HoldValueControlState();
}

class _HoldValueControlState extends State<HoldValueControl> {
  static const _popupWidth = 312.0;
  // Includes text wrapping at the narrowest supported popup width.
  static const _popupHeight = 168.0;
  static const _popupGap = 12.0;
  static const _viewportInset = 16.0;
  static const _fullRangeDragDistance = 240.0;

  OverlayEntry? _overlayEntry;
  var _activeValue = 0.0;
  var _startValue = 0.0;
  Offset? _startPosition;
  var _changedDuringHold = false;

  @override
  void dispose() {
    _removeOverlay();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPressStart: widget.enabled ? _startHold : null,
      onLongPressMoveUpdate: widget.enabled ? _updateHold : null,
      onLongPressEnd: widget.enabled ? _endHold : null,
      onLongPressCancel: widget.enabled ? _cancelHold : null,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          border: widget.enabled
              ? null
              : Border.all(color: Theme.of(context).disabledColor),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                widget.kind == HoldValueKind.hue
                    ? Icons.palette_outlined
                    : Icons.brightness_6_outlined,
                size: 18,
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 52,
                height: 12,
                child: _GradientTrack(
                  kind: widget.kind,
                  value: widget.value,
                  brightnessColor: widget.brightnessColor,
                  compact: true,
                ),
              ),
              const SizedBox(width: 6),
              Text(widget.label),
            ],
          ),
        ),
      ),
    );
  }

  void _startHold(LongPressStartDetails details) {
    _startValue = widget.value.clamp(0.0, 1.0);
    _activeValue = _startValue;
    _startPosition = details.globalPosition;
    _changedDuringHold = false;
    _showOverlay();
  }

  void _updateHold(LongPressMoveUpdateDetails details) {
    final start = _startPosition;
    if (start == null) {
      return;
    }
    final nextValue =
        (_startValue +
                (details.globalPosition.dx - start.dx) / _fullRangeDragDistance)
            .clamp(0.0, 1.0);
    if ((nextValue - _activeValue).abs() < 0.001) {
      return;
    }
    _activeValue = nextValue;
    _changedDuringHold = true;
    widget.onPreview(_activeValue);
    _overlayEntry?.markNeedsBuild();
  }

  void _endHold(LongPressEndDetails _) {
    if (_changedDuringHold) {
      widget.onCommit(_activeValue);
    }
    _clearHold();
  }

  void _cancelHold() => _clearHold();

  void _clearHold() {
    _startPosition = null;
    _changedDuringHold = false;
    _removeOverlay();
  }

  void _showOverlay() {
    _removeOverlay();
    final overlay = Overlay.of(context, rootOverlay: true);
    final overlayBox = overlay.context.findRenderObject()! as RenderBox;
    final targetBox = context.findRenderObject()! as RenderBox;
    if (!overlayBox.hasSize || !targetBox.hasSize) {
      return;
    }
    final targetTopLeft = targetBox.localToGlobal(
      Offset.zero,
      ancestor: overlayBox,
    );
    final targetRect = targetTopLeft & targetBox.size;
    final popupWidth = math
        .min(
          _popupWidth,
          math.max(0, overlayBox.size.width - _viewportInset * 2),
        )
        .toDouble();
    final maxLeft = math.max(
      _viewportInset,
      overlayBox.size.width - popupWidth - _viewportInset,
    );
    final left = (targetRect.center.dx - popupWidth / 2)
        .clamp(_viewportInset, maxLeft)
        .toDouble();
    final maxTop = math.max(
      _viewportInset,
      overlayBox.size.height - _popupHeight - _viewportInset,
    );
    final above = targetRect.top - _popupHeight - _popupGap;
    final top =
        (above >= _viewportInset ? above : targetRect.bottom + _popupGap)
            .clamp(_viewportInset, maxTop)
            .toDouble();
    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        left: left,
        top: top,
        width: popupWidth,
        child: IgnorePointer(
          child: _HoldValuePopup(
            kind: widget.kind,
            value: _activeValue,
            brightnessColor: widget.brightnessColor,
          ),
        ),
      ),
    );
    overlay.insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }
}

class _HoldValuePopup extends StatelessWidget {
  const _HoldValuePopup({
    required this.kind,
    required this.value,
    required this.brightnessColor,
  });

  final HoldValueKind kind;
  final double value;
  final Color brightnessColor;

  @override
  Widget build(BuildContext context) {
    final isHue = kind == HoldValueKind.hue;
    return Material(
      key: const Key('hold-value-popup'),
      elevation: 10,
      shadowColor: Colors.black54,
      borderRadius: BorderRadius.circular(20),
      color: Theme.of(context).colorScheme.surface,
      child: SizedBox(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                isHue ? 'Колір' : 'Яскравість ${(value * 100).round()}%',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 34,
                child: _GradientTrack(
                  kind: kind,
                  value: value,
                  brightnessColor: brightnessColor,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Ведіть пальцем горизонтально. Значення передається під час руху.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GradientTrack extends StatelessWidget {
  const _GradientTrack({
    required this.kind,
    required this.value,
    required this.brightnessColor,
    this.compact = false,
  });

  final HoldValueKind kind;
  final double value;
  final Color brightnessColor;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final isHue = kind == HoldValueKind.hue;
    final selectedColor = isHue
        ? colorFromRgb(lotusHueColor(value))
        : Color.lerp(Colors.black, brightnessColor, value)!;
    final markerSize = compact ? 10.0 : 26.0;
    return DecoratedBox(
      key: compact ? null : const Key('hold-value-gradient'),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        gradient: LinearGradient(
          colors: isHue
              ? lotusHueGradient
              : <Color>[Colors.black, brightnessColor],
        ),
      ),
      child: Align(
        alignment: Alignment(value * 2 - 1, 0),
        child: Container(
          width: markerSize,
          height: markerSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: selectedColor,
            border: Border.all(
              color: isHue ? Colors.white : Colors.white70,
              width: compact ? 1 : 2,
            ),
            boxShadow: compact
                ? null
                : const <BoxShadow>[
                    BoxShadow(color: Colors.black38, blurRadius: 4),
                  ],
          ),
        ),
      ),
    );
  }
}
