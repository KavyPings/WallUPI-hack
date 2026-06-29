import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import '../theme/app_theme.dart';
import '../providers/app_provider.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import 'payment_success_screen.dart';
import 'offline_payment_helper.dart';

/// Strong warning screen (score 80–94).
///
/// Shows full risk breakdown, risk graph, highlighted SMS phrases,
/// and requires checkbox confirmation before proceeding.
///
/// Returns `true` via Navigator.pop if payment was processed,
/// `false`/null if cancelled — so the caller can call clearRiskSession().
class RiskWarningScreen extends StatefulWidget {
  final RiskSessionContext session;

  const RiskWarningScreen({
    super.key,
    required this.session,
  });

  @override
  State<RiskWarningScreen> createState() => _RiskWarningScreenState();
}

class _RiskWarningScreenState extends State<RiskWarningScreen>
    with SingleTickerProviderStateMixin {
  bool _confirmChecked = false;
  late AnimationController _animController;
  late Animation<double> _scaleAnim;
  Map<String, dynamic>? _explanation;
  bool _loadingExplanation = true;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _scaleAnim = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.elasticOut),
    );
    _animController.forward();
    _loadExplanation();
  }

  Future<void> _loadExplanation() async {
    final result = await ApiService.explainRisk(
      score: widget.session.result.score,
      factors: widget.session.result.factors,
      interventionLevel: widget.session.result.interventionLevel,
      smsText: widget.session.smsText ?? '',
    );
    if (mounted) {
      setState(() {
        _explanation = result;
        _loadingExplanation = false;
      });
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _proceedPayment() async {
    if (!_confirmChecked) return;

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

    // Return true to signal successful payment to SendMoneyScreen
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
    final riskColor = AppTheme.getRiskColor(score);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel();
      },
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 8),

                // Close button
                Align(
                  alignment: Alignment.topRight,
                  child: IconButton(
                    onPressed: _cancel,
                    icon: const Icon(Icons.close),
                  ),
                ),

                // ── RISK SCORE CIRCLE ────────────────────────────────────
                ScaleTransition(
                  scale: _scaleAnim,
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppTheme.surfaceContainerHighest,
                      border: Border.all(color: riskColor, width: 4),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '$score%',
                            style: GoogleFonts.inter(
                              fontSize: 36,
                              fontWeight: FontWeight.bold,
                              color: riskColor,
                            ),
                          ),
                          Text(
                            'RISK',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: riskColor,
                              letterSpacing: 2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Title
                Text(
                  '⚠️ High Risk Transaction',
                  style: GoogleFonts.inter(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: riskColor,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  widget.session.result.interventionMessage,
                  style: GoogleFonts.inter(
                      fontSize: 14, color: AppTheme.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),

                // ── TRANSACTION DETAILS ──────────────────────────────────
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                    border: Border.all(color: AppTheme.outlineVariant),
                  ),
                  child: Column(
                    children: [
                      _detailRow('To', widget.session.recipientName),
                      const Divider(height: 20),
                      _detailRow('UPI ID', widget.session.recipientUpiId),
                      const Divider(height: 20),
                      _detailRow(
                          'Amount',
                          '₹${widget.session.amount.toStringAsFixed(0)}'),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // ── RISK FACTORS CHART ───────────────────────────────────
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                    border: Border.all(color: AppTheme.outlineVariant),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Risk Factor Breakdown',
                        style: GoogleFonts.inter(
                            fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 200,
                        child: _buildRiskChart(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // ── RISK FACTORS LIST (with contribution %) ──────────────
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                    border: Border.all(color: AppTheme.outlineVariant),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Why this is risky',
                        style: GoogleFonts.inter(
                            fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 12),
                      ...widget.session.result.factors
                          .map((f) => _factorTile(f,
                              total: widget.session.result.factors
                                  .fold(0, (s, x) => s + x.contribution))),
                    ],
                  ),
                ),

                // ── SMS HIGHLIGHT ────────────────────────────────────────
                if (widget.session.smsText != null &&
                    widget.session.smsText!.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  _buildSmsHighlight(),
                ],

                // ── EXPERT EXPLANATION ───────────────────────────────────
                if (!_loadingExplanation && _explanation != null) ...[
                  const SizedBox(height: 20),
                  _buildExplanationCard(),
                ],
                const SizedBox(height: 24),

                // ── CHECKBOX (required for strong warning) ───────────────
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                    border: Border.all(color: riskColor),
                  ),
                  child: Row(
                    children: [
                      Checkbox(
                        value: _confirmChecked,
                        onChanged: (v) =>
                            setState(() => _confirmChecked = v ?? false),
                        activeColor: riskColor,
                      ),
                      Expanded(
                        child: Text(
                          'I understand the risk and still want to continue',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: AppTheme.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // ── ACTION BUTTONS ───────────────────────────────────────
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _cancel,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.surfaceContainerHigh,
                            foregroundColor: AppTheme.onSurface,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                            ),
                          ),
                          child: Text('❌ Cancel',
                              style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: SizedBox(
                        height: 52,
                        child: ElevatedButton(
                          onPressed:
                              _confirmChecked ? _proceedPayment : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: riskColor,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                            ),
                          ),
                          child: Text('✅ Proceed',
                              style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: GoogleFonts.inter(
                fontSize: 13, color: AppTheme.onSurfaceVariant)),
        Text(value,
            style: GoogleFonts.inter(
                fontSize: 14, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _buildRiskChart() {
    final factors = widget.session.result.factors.take(5).toList();
    if (factors.isEmpty) return const Center(child: Text('No data'));

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: 35,
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              return BarTooltipItem(
                '${factors[group.x.toInt()].factor}\n+${rod.toY.toInt()}',
                GoogleFonts.inter(
                    fontSize: 11,
                    color: AppTheme.surfaceContainerLow,
                    fontWeight: FontWeight.w500),
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          show: true,
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final idx = value.toInt();
                if (idx >= factors.length) return const Text('');
                final label = factors[idx].factor;
                return SideTitleWidget(
                  axisSide: meta.axisSide,
                  child: Text(
                    label.length > 8 ? '${label.substring(0, 8)}...' : label,
                    style: GoogleFonts.inter(
                        fontSize: 9, color: AppTheme.textLight),
                  ),
                );
              },
              reservedSize: 30,
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (value, meta) {
                return Text('${value.toInt()}',
                    style: GoogleFonts.inter(
                        fontSize: 10, color: AppTheme.textLight));
              },
            ),
          ),
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (value) =>
              const FlLine(color: AppTheme.outlineVariant, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        barGroups: factors.asMap().entries.map((entry) {
          final color = entry.value.severity == 'high'
              ? AppTheme.danger
              : entry.value.severity == 'medium'
                  ? AppTheme.warningOrange
                  : AppTheme.riskMedium;
          return BarChartGroupData(
            x: entry.key,
            barRods: [
              BarChartRodData(
                toY: entry.value.contribution.toDouble(),
                color: color,
                width: 22,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(6)),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _factorTile(RiskFactor factor, {int total = 100}) {
    final severityColor = factor.severity == 'high'
        ? AppTheme.danger
        : factor.severity == 'medium'
            ? AppTheme.warningOrange
            : AppTheme.riskMedium;

    // Contribution percentage for explainability
    final pct = total > 0
        ? ((factor.contribution / total) * 100).round()
        : 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(
              color: severityColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  factor.factor,
                  style: GoogleFonts.inter(
                      fontSize: 14, fontWeight: FontWeight.w600),
                ),
                Text(
                  factor.description,
                  style: GoogleFonts.inter(
                      fontSize: 12, color: AppTheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '+${factor.contribution}',
                  style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: severityColor),
                ),
              ),
              Text(
                '$pct% of risk',
                style: GoogleFonts.inter(
                    fontSize: 10, color: AppTheme.textLight),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSmsHighlight() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: AppTheme.danger),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.sms_outlined, size: 18, color: AppTheme.danger),
              const SizedBox(width: 8),
              Text(
                'Suspicious SMS Content',
                style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.danger),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildHighlightedText(widget.session.smsText!),
        ],
      ),
    );
  }

  Widget _buildHighlightedText(String text) {
    const dangerWords = [
      'urgent', 'blocked', 'kyc', 'send', 'otp', 'pin', 'expire',
      'verify', 'click', 'prize', 'won', 'lottery', 'immediately',
      'suspended', 'congratulations', 'reward', 'password',
    ];

    final words = text.split(' ');
    final spans = words.map((word) {
      final isHighlighted =
          dangerWords.any((d) => word.toLowerCase().contains(d));
      return TextSpan(
        text: '$word ',
        style: GoogleFonts.inter(
          fontSize: 13,
          color: isHighlighted ? AppTheme.danger : AppTheme.textPrimary,
          fontWeight:
              isHighlighted ? FontWeight.bold : FontWeight.normal,
          backgroundColor:
              isHighlighted ? AppTheme.surfaceContainerHighest : null,
        ),
      );
    }).toList();

    return RichText(text: TextSpan(children: spans));
  }

  Widget _buildExplanationCard() {
    final explanations =
        _explanation?['detailed_explanations'] as List? ?? [];
    if (explanations.isEmpty) return const SizedBox();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: AppTheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Expert Analysis',
            style: GoogleFonts.inter(
                fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            _explanation?['narrative'] ?? '',
            style: GoogleFonts.inter(
                fontSize: 13, color: AppTheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          ...explanations.take(3).map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(e['icon'] ?? '⚠️',
                        style: const TextStyle(fontSize: 18)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            e['title'] ?? '',
                            style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w600),
                          ),
                          Text(
                            e['advice'] ?? '',
                            style: GoogleFonts.inter(
                                fontSize: 12,
                                color: AppTheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}
