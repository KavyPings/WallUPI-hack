import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

/// Small indicator pill showing whether an AI service (Cloud AI / TinyBERT) is live.
///
/// [isOn] — null = still checking (dot fades), true = green, false = dimmed.
class AiStatusPill extends StatelessWidget {
  final String label;
  final bool? isOn;

  const AiStatusPill({super.key, required this.label, required this.isOn});

  @override
  Widget build(BuildContext context) {
    final bool active = isOn == true;
    final bool checking = isOn == null;

    final Color dotColor = checking
        ? AppTheme.outlineVariant
        : active
            ? AppTheme.riskSafe
            : AppTheme.outlineVariant;

    final Color borderColor = active
        ? AppTheme.riskSafe.withValues(alpha: 0.35)
        : AppTheme.outlineVariant;

    final Color textColor = active ? AppTheme.riskSafe : AppTheme.outline;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.surfaceContainer,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedOpacity(
            opacity: checking ? 0.4 : 1.0,
            duration: const Duration(milliseconds: 400),
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
            ),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }
}
