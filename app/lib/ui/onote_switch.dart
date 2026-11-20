import 'package:flutter/material.dart';

/// A switch whose thumb and track keep their contrast while hovered.
class OnoteSwitch extends StatelessWidget {
  const OnoteSwitch(
      {super.key,
      required this.value,
      required this.onChanged,
      this.compact = false});

  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final control = Switch(
      value: value,
      onChanged: onChanged,
      overlayColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.focused)
              ? colors.primary.withValues(alpha: .15)
              : Colors.transparent),
      thumbColor: const WidgetStatePropertyAll(Colors.transparent),
      trackColor: const WidgetStatePropertyAll(Colors.transparent),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      trackOutlineWidth: const WidgetStatePropertyAll(0),
    );
    final visual = Stack(
      alignment: Alignment.center,
      children: [
        control,
        IgnorePointer(
          child: Container(
            width: 52,
            height: 32,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: colors.onSurface
                  .withValues(alpha: onChanged == null ? .12 : .24),
              borderRadius: BorderRadius.circular(16),
            ),
            child: AnimatedAlign(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 160),
              curve: Curves.easeOutCubic,
              alignment: value
                  ? AlignmentDirectional.centerEnd
                  : AlignmentDirectional.centerStart,
              child: const SizedBox.square(
                dimension: 24,
                child: DecoratedBox(
                    decoration: BoxDecoration(
                        shape: BoxShape.circle, color: Colors.white)),
              ),
            ),
          ),
        ),
      ],
    );
    // Scale equally so the thumb stays circular; retain the full hit target.
    return compact
        ? SizedBox(
            width: 56,
            height: 48,
            child: Transform.scale(scale: .8, child: visual),
          )
        : visual;
  }
}
