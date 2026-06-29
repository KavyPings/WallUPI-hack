import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:percent_indicator/circular_percent_indicator.dart';
import '../theme/app_theme.dart';
import '../providers/app_provider.dart';
import '../models/models.dart';
import '../services/risk_decision_engine.dart';
import 'payment_success_screen.dart';
import 'offline_payment_helper.dart';

/// Critical intervention screen (score 95–100).
///
/// Shows a 10-second forced delay countdown, then requires checkbox
/// confirmation before allowing the transaction to proceed.
///
/// Returns `true` via Navigator.pop if payment was processed,
/// `false`/null if cancelled — so the caller can call clearRiskSession().
class CriticalDelayScreen extends StatefulWidget {
  final RiskSessionContext session;

  const CriticalDelayScreen({
    super.key,
    required this.session,
  });

  @override
  State<CriticalDelayScreen> createState() => _CriticalDelayScreenState();
}

class _CriticalDelayScreenState extends State<CriticalDelayScreen>
    with TickerProviderStateMixin {
  int _secondsRemaining = RiskThresholds.criticalDelaySeconds;
  Timer? _timer;
  bool _canProceed = false;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _startCountdown();
  }

  void _startCountdown() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining > 0) {
        setState(() => _secondsRemaining--);
      } else {
        timer.cancel();
        setState(() => _canProceed = true);
        _pulseController.stop();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _proceedPayment() async {
    if (!_canProceed) return;

    if (widget.session.isOffline) {
      showOfflinePaymentPicker(
        context,
        amount: widget.session.amount,
        recipientName: widget.session.recipientName,
        recipientUpiId: widget.session.recipientUpiId,
        riskScore: widget.session.result.score,
        note: widget.session.note,
        wasCorrelatedWithSms: widget.session.smsText != null,
      );
      return;
    }

    final provider = context.read<AppProvider>();
    await provider.processPayment(
      recipientName: widget.session.recipientName,
      recipientUpiId: widget.session.recipientUpiId,
      amount: widget.session.amount,
      note: widget.session.note,
      riskScore: widget.session.result.score,
    );

    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => PaymentSuccessScreen(
          amount: widget.session.amount,
          recipientName: widget.session.recipientName,
          recipientUpiId: widget.session.recipientUpiId,
          riskScore: widget.session.result.score,
        ),
      ),
      (route) => route.isFirst,
    );
  }

  void _cancel() {
    // Signal cancellation back to SendMoneyScreen (which will call clearRiskSession)
    Navigator.pop(context, false);
  }

  @override
  Widget build(BuildContext context) {
    final score = widget.session.result.score;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel();
      },
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: SafeArea(
          child: Column(
            children: [
              // ── STICKY COUNTDOWN BANNER (always visible) ──────────────────
              AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
                decoration: BoxDecoration(
                  color: _canProceed
                      ? AppTheme.surfaceContainerLow
                      : AppTheme.surfaceContainerLow,
                  border: Border(
                    bottom: BorderSide(
                      color: _canProceed
                          ? AppTheme.secondary
                          : AppTheme.danger,
                      width: 1,
                    ),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _canProceed ? Icons.check_circle_rounded : Icons.timer_rounded,
                      color: _canProceed ? AppTheme.secondary : AppTheme.danger,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    if (!_canProceed) ...[
                      Text(
                        'Transaction paused — ',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: AppTheme.onSurface,
                        ),
                      ),
                      // Big countdown number
                      Text(
                        '$_secondsRemaining',
                        style: GoogleFonts.inter(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.danger,
                        ),
                      ),
                      Text(
                        's remaining',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: AppTheme.onSurface,
                        ),
                      ),
                    ] else
                      Text(
                        'Wait complete — you may now proceed',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.secondary,
                        ),
                      ),
                  ],
                ),
              ),

              // ── SCROLLABLE CONTENT ────────────────────────────────────────
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      const SizedBox(height: 20),


                // ── CRITICAL ALERT HEADER ────────────────────────────────
                ScaleTransition(
                  scale: _pulseAnim,
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppTheme.surfaceContainerHighest,
                      border: Border.all(color: AppTheme.danger, width: 3),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.surfaceContainerHighest,
                          blurRadius: 30,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Icon(Icons.gpp_bad_rounded,
                          color: AppTheme.danger, size: 40),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                Text(
                  '🔴 CRITICAL RISK DETECTED',
                  style: GoogleFonts.inter(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.danger,
                    letterSpacing: 1,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Transaction paused for your safety',
                  style: GoogleFonts.inter(
                      fontSize: 16, color: AppTheme.onSurface),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),

                // ── COUNTDOWN TIMER ──────────────────────────────────────
                CircularPercentIndicator(
                  radius: 80,
                  lineWidth: 8,
                  percent: _canProceed
                      ? 1.0
                      : (RiskThresholds.criticalDelaySeconds -
                              _secondsRemaining) /
                          RiskThresholds.criticalDelaySeconds,
                  center: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _canProceed ? '✓' : '$_secondsRemaining',
                        style: GoogleFonts.inter(
                          fontSize: _canProceed ? 36 : 48,
                          fontWeight: FontWeight.bold,
                          color: _canProceed
                              ? AppTheme.secondary
                              : AppTheme.onSurface,
                        ),
                      ),
                      if (!_canProceed)
                        Text(
                          'seconds',
                          style: GoogleFonts.inter(
                              fontSize: 12, color: AppTheme.onSurfaceVariant),
                        ),
                    ],
                  ),
                  progressColor:
                      _canProceed ? AppTheme.secondary : AppTheme.danger,
                  backgroundColor: AppTheme.surfaceContainerHigh,
                  circularStrokeCap: CircularStrokeCap.round,
                  animation: false,
                ),
                const SizedBox(height: 24),

                if (!_canProceed)
                  Text(
                    'Please wait while we give you time to reconsider...',
                    style: GoogleFonts.inter(
                        fontSize: 14, color: AppTheme.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),

                const SizedBox(height: 28),

                // ── TRANSACTION INFO ─────────────────────────────────────
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceContainer,
                    borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                    border: Border.all(
                        color: AppTheme.surfaceContainerHigh),
                  ),
                  child: Column(
                    children: [
                      _infoRow('To', widget.session.recipientName),
                      const Divider(color: AppTheme.outlineVariant, height: 20),
                      _infoRow('Amount',
                          '₹${widget.session.amount.toStringAsFixed(0)}'),
                      const Divider(color: AppTheme.outlineVariant, height: 20),
                      _infoRow('Risk Score', '$score% — CRITICAL'),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // ── RISK FACTORS ─────────────────────────────────────────
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                    border: Border.all(
                        color: AppTheme.surfaceContainerHighest),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Why this was blocked:',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ...widget.session.result.factors
                          .take(4)
                          .map((f) => Padding(
                                padding:
                                    const EdgeInsets.only(bottom: 10),
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    const Text('🚩 ',
                                        style:
                                            TextStyle(fontSize: 14)),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            f.factor,
                                            style: GoogleFonts.inter(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: AppTheme.onSurface,
                                            ),
                                          ),
                                          Text(
                                            f.description,
                                            style: GoogleFonts.inter(
                                                fontSize: 12,
                                                color: AppTheme.onSurfaceVariant),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 7, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: AppTheme.surfaceContainerHighest,
                                        borderRadius:
                                            BorderRadius.circular(AppTheme.radiusSmall),
                                        border: Border.all(color: AppTheme.danger),
                                      ),
                                      child: Text(
                                        '+${f.contribution}',
                                        style: GoogleFonts.inter(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: AppTheme.onSurface,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              )),
                    ],
                  ),
                ),

                // ── SMS CONTENT ──────────────────────────────────────────
                if (widget.session.smsText != null &&
                    widget.session.smsText!.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceContainer,
                      borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                      border: Border.all(
                          color: AppTheme.surfaceContainerHighest),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.sms_failed,
                                size: 16, color: AppTheme.danger),
                            const SizedBox(width: 8),
                            Text(
                              'Related Suspicious SMS',
                              style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.danger),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.session.smsText!,
                          style: GoogleFonts.inter(
                              fontSize: 12, color: AppTheme.onSurface),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 28),

                // ── ACTION BUTTONS ───────────────────────────────────────
                // Cancel always visible
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton.icon(
                    onPressed: _cancel,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.surfaceContainerHigh,
                      foregroundColor: AppTheme.onSurface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                      ),
                    ),
                    icon: const Icon(Icons.close, size: 20),
                    label: Text(
                      'Cancel Transaction',
                      style: GoogleFonts.inter(
                          fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Proceed button — visible only after countdown completes, no checkbox needed
                if (_canProceed)
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton.icon(
                      onPressed: _proceedPayment,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.danger,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                        ),
                      ),
                      icon: const Icon(Icons.warning_rounded, size: 20),
                      label: Text(
                        'Continue Anyway',
                        style: GoogleFonts.inter(
                            fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: GoogleFonts.inter(
                fontSize: 13, color: AppTheme.onSurfaceVariant)),
        Text(
          value,
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: label == 'Risk Score' ? AppTheme.danger : AppTheme.onSurface,
          ),
        ),
      ],
    );
  }
}
