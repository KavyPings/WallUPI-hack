import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import 'home_screen.dart';
import 'transaction_history_screen.dart' show showFlagDialog;

class PaymentSuccessScreen extends StatefulWidget {
  final double amount;
  final String recipientName;
  final String recipientUpiId;
  final int riskScore;
  final bool isOffline;
  final String? offlineMethod;

  const PaymentSuccessScreen({
    super.key,
    required this.amount,
    required this.recipientName,
    this.recipientUpiId = '',
    this.riskScore = 0,
    this.isOffline = false,
    this.offlineMethod,
  });

  @override
  State<PaymentSuccessScreen> createState() => _PaymentSuccessScreenState();
}

class _PaymentSuccessScreenState extends State<PaymentSuccessScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _scaleAnim;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _scaleAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.elasticOut),
    );
    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: const Interval(0.3, 1.0, curve: Curves.easeOut)),
    );
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.15), end: Offset.zero).animate(
      CurvedAnimation(parent: _animController, curve: const Interval(0.3, 1.0, curve: Curves.easeOut)),
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final txnId = 'WF${DateTime.now().millisecondsSinceEpoch % 100000000}';
    final timeStr = DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now());

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),

              // ── Success icon (scale-in) ──
              ScaleTransition(
                scale: _scaleAnim,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppTheme.surfaceContainerHigh,
                    border: Border.all(color: AppTheme.outlineVariant, width: 1),
                    boxShadow: const [AppTheme.innerHighlight],
                  ),
                  child: Icon(
                    widget.isOffline ? Icons.offline_bolt_rounded : Icons.check_rounded,
                    color: AppTheme.primary,
                    size: 38,
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // ── Amount + label (fade + slide up) ──
              SlideTransition(
                position: _slideAnim,
                child: FadeTransition(
                  opacity: _fadeAnim,
                  child: Column(
                    children: [
                      Text(
                        '₹${widget.amount.toStringAsFixed(0)}',
                        style: GoogleFonts.inter(
                          fontSize: 44,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.onSurface,
                          letterSpacing: -1.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        widget.isOffline ? 'Payment Initiated Offline' : 'Payment Sent Successfully',
                        style: GoogleFonts.inter(fontSize: 16, color: AppTheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 28),

                      // ── Details card ──
                      Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceContainer,
                          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                          border: Border.all(color: AppTheme.outlineVariant),
                        ),
                        child: Column(
                          children: [
                            _detailRow('Recipient', widget.recipientName),
                            const Divider(height: 1, thickness: 1, color: AppTheme.outlineVariant),
                            _detailRow('Amount', '₹${widget.amount.toStringAsFixed(2)}'),
                            const Divider(height: 1, thickness: 1, color: AppTheme.outlineVariant),
                            _detailRow('Date', timeStr),
                            const Divider(height: 1, thickness: 1, color: AppTheme.outlineVariant),
                            if (widget.isOffline) ...[
                              _detailRow('Offline Channel', widget.offlineMethod ?? 'Simulated'),
                              const Divider(height: 1, thickness: 1, color: AppTheme.outlineVariant),
                            ],
                            _detailRow('Txn ID', txnId, mono: true),
                            if (widget.riskScore > 20) ...[
                              const Divider(height: 1, thickness: 1, color: AppTheme.outlineVariant),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('Risk Level', style: GoogleFonts.inter(fontSize: 13, color: AppTheme.onSurfaceVariant)),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: AppTheme.surfaceContainerHighest,
                                        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                                        border: Border.all(color: AppTheme.getRiskColor(widget.riskScore).withValues(alpha: 0.4)),
                                      ),
                                      child: Text(
                                        '${widget.riskScore}% — ${AppTheme.getRiskLabel(widget.riskScore)}',
                                        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.getRiskColor(widget.riskScore)),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const Spacer(),

              // ── Actions ──
              FadeTransition(
                opacity: _fadeAnim,
                child: Column(
                  children: [
                    // Done button — primary (periwinkle) background
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pushAndRemoveUntil(
                            context,
                            MaterialPageRoute(builder: (_) => const HomeScreen()),
                            (route) => false,
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          foregroundColor: AppTheme.onPrimary,
                          elevation: 0,
                          shadowColor: Colors.transparent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                          ),
                        ),
                        child: Text('Done', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (widget.recipientUpiId.isNotEmpty)
                      SizedBox(
                        width: double.infinity,
                        height: 44,
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.flag_outlined, size: 15, color: AppTheme.danger),
                          label: Text('Report this recipient', style: GoogleFonts.inter(fontSize: 13, color: AppTheme.danger)),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppTheme.outlineVariant),
                            foregroundColor: AppTheme.danger,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusSmall)),
                          ),
                          onPressed: () => showFlagDialog(context, flaggedUpiId: widget.recipientUpiId, displayName: widget.recipientName),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value, {bool mono = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: GoogleFonts.inter(fontSize: 13, color: AppTheme.onSurfaceVariant)),
          const SizedBox(width: 16),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: mono
                  ? GoogleFonts.inter(fontSize: 12, color: AppTheme.onSurface, fontWeight: FontWeight.w500, letterSpacing: 0.5)
                  : GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.onSurface),
            ),
          ),
        ],
      ),
    );
  }
}
