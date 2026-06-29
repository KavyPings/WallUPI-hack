import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../providers/app_provider.dart';
import '../services/native_payment_bridge.dart';
import 'payment_success_screen.dart';

Future<void> showOfflinePaymentPicker(
  BuildContext context, {
  required double amount,
  required String recipientName,
  required String recipientUpiId,
  required int riskScore,
  required String note,
  required bool wasCorrelatedWithSms,
}) async {
  showModalBottomSheet(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      side: BorderSide(color: AppTheme.outlineVariant),
    ),
    backgroundColor: AppTheme.surfaceContainerLow,
    builder: (ctx) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Select Offline Payment Channel',
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppTheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'The server is unreachable. You can complete the transaction via official offline UPI telecom channels.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: AppTheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            _buildOption(
              context,
              icon: Icons.dialpad_rounded,
              color: AppTheme.primary,
              title: 'Dial USSD (*99#)',
              subtitle: 'Send money offline using national telecom menu dialer',
              onTap: () async {
                Navigator.pop(ctx);
                await NativePaymentBridge.launchOfflinePayment(method: 'ussd');
                _navigateToSuccess(
                  context,
                  amount: amount,
                  recipientName: recipientName,
                  recipientUpiId: recipientUpiId,
                  riskScore: riskScore,
                  offlineMethod: 'USSD (*99#)',
                );
              },
            ),
            const Divider(height: 1, color: AppTheme.outlineVariant),
            _buildOption(
              context,
              icon: Icons.phone_in_talk_rounded,
              color: AppTheme.secondary,
              title: 'Call 123PAY IVR',
              subtitle: 'Voice-based official interactive voice response UPI payment',
              onTap: () async {
                Navigator.pop(ctx);
                await NativePaymentBridge.launchOfflinePayment(method: 'ivr');
                _navigateToSuccess(
                  context,
                  amount: amount,
                  recipientName: recipientName,
                  recipientUpiId: recipientUpiId,
                  riskScore: riskScore,
                  offlineMethod: 'Voice Call (123PAY)',
                );
              },
            ),
            const Divider(height: 1, color: AppTheme.outlineVariant),
            _buildOption(
              context,
              icon: Icons.bolt_rounded,
              color: AppTheme.warningOrange,
              title: 'Simulate In-App Payment',
              subtitle: 'Proceed offline using mock in-app database logger',
              onTap: () async {
                Navigator.pop(ctx);
                final provider = context.read<AppProvider>();
                await provider.processPayment(
                  recipientName: recipientName,
                  recipientUpiId: recipientUpiId,
                  amount: amount,
                  note: note,
                  riskScore: riskScore,
                  wasCorrelatedWithSms: wasCorrelatedWithSms,
                );
                _navigateToSuccess(
                  context,
                  amount: amount,
                  recipientName: recipientName,
                  recipientUpiId: recipientUpiId,
                  riskScore: riskScore,
                  offlineMethod: 'Simulated In-App',
                );
              },
            ),
          ],
        ),
      );
    },
  );
}

Widget _buildOption(
  BuildContext context, {
  required IconData icon,
  required Color color,
  required String title,
  required String subtitle,
  required VoidCallback onTap,
}) {
  return ListTile(
    leading: Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: AppTheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: AppTheme.outlineVariant),
      ),
      child: Icon(icon, color: color, size: 20),
    ),
    title: Text(
      title,
      style: GoogleFonts.inter(
        fontWeight: FontWeight.w500,
        color: AppTheme.onSurface,
      ),
    ),
    subtitle: Text(
      subtitle,
      style: GoogleFonts.inter(
        fontSize: 12,
        color: AppTheme.onSurfaceVariant,
      ),
    ),
    trailing: const Icon(
      Icons.chevron_right,
      color: AppTheme.onSurfaceVariant,
      size: 18,
    ),
    onTap: onTap,
  );
}

void _navigateToSuccess(
  BuildContext context, {
  required double amount,
  required String recipientName,
  required String recipientUpiId,
  required int riskScore,
  required String offlineMethod,
}) {
  Navigator.pushAndRemoveUntil(
    context,
    MaterialPageRoute(
      builder: (_) => PaymentSuccessScreen(
        amount: amount,
        recipientName: recipientName,
        recipientUpiId: recipientUpiId,
        riskScore: riskScore,
        isOffline: true,
        offlineMethod: offlineMethod,
      ),
    ),
    (route) => route.isFirst,
  );
}
