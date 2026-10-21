import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Macht eine Kachel per Fernbedienung bzw. Tastatur bedienbar: Pfeiltasten
/// fokussieren, OK/Enter löst [onActivate] aus. Die Maus bleibt unberührt.
class TvFocus extends StatelessWidget {
  const TvFocus({
    super.key,
    required this.child,
    required this.onActivate,
    required this.onFocusChange,
    this.onSecondary,
    this.autofocus = false,
  });

  final Widget child;
  final VoidCallback? onActivate;

  /// Meldet, ob der Fokusrahmen sichtbar sein soll (nur bei Tastatur/Fernbedienung).
  final ValueChanged<bool> onFocusChange;
  final bool autofocus;

  /// Menü-Taste der Fernbedienung bzw. „F“ auf der Tastatur (z. B. Favorit).
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      enabled: onActivate != null,
      autofocus: autofocus,
      onShowFocusHighlight: onFocusChange,
      shortcuts: onSecondary == null
          ? null
          : const {
              SingleActivator(LogicalKeyboardKey.contextMenu): _SecondaryIntent(),
              SingleActivator(LogicalKeyboardKey.keyF): _SecondaryIntent(),
            },
      // Fokussierte Kachel ins Bild scrollen, auch in waagerechten Reihen.
      onFocusChange: (focused) {
        if (focused) Scrollable.ensureVisible(context, alignment: 0.5, duration: const Duration(milliseconds: 180));
      },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            onActivate?.call();
            return null;
          },
        ),
        _SecondaryIntent: CallbackAction<_SecondaryIntent>(
          onInvoke: (_) {
            onSecondary?.call();
            return null;
          },
        ),
      },
      child: child,
    );
  }
}

class _SecondaryIntent extends Intent {
  const _SecondaryIntent();
}

/// Weißer Rahmen um das fokussierte Element, gut sichtbar auf dem Fernseher.
class FocusRing extends StatelessWidget {
  const FocusRing({super.key, required this.visible, required this.radius, required this.child});

  final bool visible;
  final double radius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: visible ? Colors.white : Colors.transparent, width: 2.5),
      ),
      child: child,
    );
  }
}

/// Tasten der Fernbedienung, die Flutter nicht von selbst als „Zurück“ deutet.
const tvBackKeys = [LogicalKeyboardKey.goBack, LogicalKeyboardKey.browserBack, LogicalKeyboardKey.escape];
