import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../providers/app_provider.dart';
import '../services/api_service.dart';
import '../services/native_sms_bridge.dart';
import '../services/sms_detector.dart';
import '../theme/app_theme.dart';
import 'transaction_history_screen.dart' show showFlagDialog;

class SmsAnalysisScreen extends StatefulWidget {
  const SmsAnalysisScreen({super.key});

  @override
  State<SmsAnalysisScreen> createState() => _SmsAnalysisScreenState();
}

class _SmsAnalysisScreenState extends State<SmsAnalysisScreen>
    with WidgetsBindingObserver {
  final _smsInputController = TextEditingController();
  final _senderController = TextEditingController(text: '+91-9999888777');
  bool _isAnalyzing = false;
  bool _isSyncing = false;
  int _selectedTab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoSync());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _smsInputController.dispose();
    _senderController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      _autoSync();
    }
  }

  Future<void> _autoSync() async {
    if (!mounted) return;
    setState(() => _isSyncing = true);
    final provider = context.read<AppProvider>();
    await provider.refreshNativeSmsStatus();
    await provider.syncNativeSmsMessages();
    if (!mounted) return;
    setState(() => _isSyncing = false);
  }

  Future<void> _addAndAnalyzeSms() async {
    final body = _smsInputController.text.trim();
    final sender = _senderController.text.trim();
    if (body.isEmpty) return;

    setState(() => _isAnalyzing = true);
    final provider = context.read<AppProvider>();
    final sms = await provider.addSms(sender: sender, body: body);

    if (!mounted) return;
    setState(() {
      _isAnalyzing = false;
      _selectedTab = 0;
    });
    _smsInputController.clear();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          sms.isFlagged ? 'Suspicious SMS detected locally.' : 'SMS analyzed locally.',
          style: GoogleFonts.inter(),
        ),
        backgroundColor: sms.isFlagged ? AppTheme.danger : AppTheme.secondary,
      ),
    );
  }

  Future<void> _requestPermissions() async {
    setState(() => _isSyncing = true);
    final granted = await context.read<AppProvider>().requestSmsPermissions();
    if (!mounted) return;
    setState(() => _isSyncing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          granted ? 'SMS permissions granted.' : 'SMS permissions not granted.',
          style: GoogleFonts.inter(),
        ),
        backgroundColor: granted ? AppTheme.secondary : AppTheme.warningOrange,
      ),
    );
  }

  Future<void> _syncInbox() async {
    setState(() => _isSyncing = true);
    final count = await context.read<AppProvider>().syncNativeSmsMessages();
    if (!mounted) return;
    setState(() => _isSyncing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Synced $count device SMS message(s).',
          style: GoogleFonts.inter(),
        ),
        backgroundColor: AppTheme.primary,
      ),
    );
  }

  void _showAnalysisDetail(SmsMessage sms) {
    final riskScore = (sms.localRiskScore * 100).round();
    final riskColor = AppTheme.getRiskColor(riskScore);
    final prettyCategory = sms.classification.replaceAll('_', ' ').toUpperCase();
    const cloudColor = Color(0xFF7C3AED);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
        side: BorderSide(color: AppTheme.outlineVariant),
      ),
      builder: (ctx) {
        CloudReviewResult? cloudResult;
        bool cloudLoading = false;
        String? cloudError;

        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> runCloudReview() async {
              setModalState(() {
                cloudLoading = true;
                cloudError = null;
              });
              final result = await ApiService.cloudReviewSms(
                sanitizedBody: sms.sanitizedPreview ?? sms.body,
                localRiskScore: sms.localRiskScore,
                classification: sms.classification,
                sender: sms.sender,
                flags: sms.flags,
                escalationReason: sms.cloudEscalationReason ?? '',
              );
              setModalState(() {
                cloudResult = result;
                cloudLoading = false;
                if (result == null) {
                  cloudError = 'Cloud review unavailable — backend not configured or unreachable.';
                }
              });
            }

            return DraggableScrollableSheet(
              initialChildSize: 0.74,
              maxChildSize: 0.92,
              minChildSize: 0.5,
              expand: false,
              builder: (_, scrollController) {
                return SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                            color: AppTheme.outlineVariant,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'On-Device SMS Analysis',
                        style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 16),
                      Center(
                        child: Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppTheme.surfaceContainerHighest,
                            border: Border.all(color: riskColor, width: 2),
                          ),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '$riskScore%',
                                  style: GoogleFonts.inter(
                                    fontSize: riskScore >= 100 ? 18 : 28,
                                    fontWeight: FontWeight.bold,
                                    color: riskColor,
                                  ),
                                ),
                                Text('Risk', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary)),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _infoPill(prettyCategory, riskColor),
                          _infoPill(sms.analysisSource.replaceAll('_', ' '), AppTheme.primary),
                          if (sms.modelConfidence != null)
                            _infoPill('Model ${(sms.modelConfidence! * 100).round()}%', AppTheme.secondary),
                          if (sms.shouldEscalateToCloud && cloudResult == null)
                            _infoPill('Cloud Pending', AppTheme.warningOrange),
                          if (cloudResult != null)
                            _infoPill('+ Cloud LLM', cloudColor),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Text('Message Content', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      _surfaceText(sms.body),
                      if (sms.summary != null && sms.summary!.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        Text('Summary', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        _surfaceText(sms.summary!),
                      ],
                      if (sms.flags.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        Text('Detected Signals', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: sms.flags.map((flag) {
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: AppTheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                                border: Border.all(color: AppTheme.danger),
                              ),
                              child: Text(
                                SmsDetector.getFlagDescription(flag),
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: AppTheme.danger,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                      if (sms.extractedMetadata != null && !sms.extractedMetadata!.isEmpty) ...[
                        const SizedBox(height: 20),
                        Text('Extracted Transaction Signals', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 10),
                        ..._metadataRows(sms.extractedMetadata!),
                      ],
                      if (sms.shouldEscalateToCloud && sms.sanitizedPreview != null) ...[
                        const SizedBox(height: 20),
                        Text('Sanitized Cloud Preview', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        _surfaceText(sms.sanitizedPreview!),
                        if (sms.cloudEscalationReason != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            sms.cloudEscalationReason!,
                            style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary),
                          ),
                        ],
                      ],
                      // ── Cloud AI Review ──────────────────────────────────
                      if (sms.shouldEscalateToCloud) ...[
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            const Icon(Icons.cloud_outlined, size: 18, color: cloudColor),
                            const SizedBox(width: 8),
                            Text(
                              'Cloud AI Review',
                              style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'GPT-OSS 120B on Amazon Bedrock',
                          style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary),
                        ),
                        const SizedBox(height: 12),
                        if (!cloudLoading && cloudResult == null && cloudError == null)
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: cloudColor,
                                side: const BorderSide(color: cloudColor),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                              ),
                              onPressed: runCloudReview,
                              icon: const Icon(Icons.psychology_outlined, size: 18),
                              label: Text(
                                'Request Cloud AI Review',
                                style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                              ),
                            ),
                          ),
                        if (cloudLoading)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: AppTheme.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                              border: Border.all(color: cloudColor.withOpacity(0.3)),
                            ),
                            child: Column(
                              children: [
                                const CircularProgressIndicator(color: cloudColor, strokeWidth: 2),
                                const SizedBox(height: 12),
                                Text(
                                  'Consulting GPT-OSS 120B...',
                                  style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textSecondary),
                                ),
                              ],
                            ),
                          ),
                        if (cloudError != null)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: AppTheme.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                              border: Border.all(color: AppTheme.danger.withOpacity(0.4)),
                            ),
                            child: Text(
                              cloudError!,
                              style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary),
                            ),
                          ),
                        if (cloudResult != null)
                          _cloudResultCard(cloudResult!, cloudColor),
                      ],
                      const SizedBox(height: 24),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _cloudResultCard(CloudReviewResult result, Color cloudColor) {
    final cloudRiskColor = AppTheme.getRiskColor(result.riskScore);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: cloudColor.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.surfaceContainerHighest,
                  border: Border.all(color: cloudRiskColor, width: 2),
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${result.riskScore}%',
                        style: GoogleFonts.inter(
                          fontSize: result.riskScore >= 100 ? 13 : 18,
                          fontWeight: FontWeight.bold,
                          color: cloudRiskColor,
                        ),
                      ),
                      Text('Risk', style: GoogleFonts.inter(fontSize: 9, color: AppTheme.textSecondary)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      result.classification.replaceAll('_', ' ').toUpperCase(),
                      style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: cloudRiskColor),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Intervention: ${result.interventionLevel}',
                      style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary),
                    ),
                    Text(
                      'Confidence: ${(result.confidence * 100).round()}%',
                      style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (result.explanation.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              result.explanation,
              style: GoogleFonts.inter(fontSize: 12, color: AppTheme.onSurface, height: 1.5),
            ),
          ],
          if (result.keyIndicators.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: result.keyIndicators.map((indicator) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: cloudColor.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                  border: Border.all(color: cloudColor.withOpacity(0.35)),
                ),
                child: Text(
                  indicator,
                  style: GoogleFonts.inter(fontSize: 10, color: cloudColor, fontWeight: FontWeight.w500),
                ),
              )).toList(),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            result.modelUsed,
            style: GoogleFonts.inter(fontSize: 10, color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _infoPill(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppTheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(color: color),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: color,
        ),
      ),
    );
  }

  Widget _surfaceText(String value) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.cardDecoration(
        color: AppTheme.surfaceContainerHigh,
        radius: AppTheme.radiusMedium,
      ),
      child: Text(
        value,
        style: GoogleFonts.inter(fontSize: 13, color: AppTheme.onSurface, height: 1.5),
      ),
    );
  }

  List<Widget> _metadataRows(SmsMetadata metadata) {
    final rows = <Widget>[];
    if (metadata.upiIds.isNotEmpty) rows.add(_metadataRow('UPI IDs', metadata.upiIds.join(', ')));
    if (metadata.phones.isNotEmpty) rows.add(_metadataRow('Phone Numbers', metadata.phones.join(', ')));
    if (metadata.amounts.isNotEmpty) rows.add(_metadataRow('Amounts', metadata.amounts.join(', ')));
    if (metadata.urls.isNotEmpty) rows.add(_metadataRow('URLs', metadata.urls.join(', ')));
    if (metadata.names.isNotEmpty) rows.add(_metadataRow('Names', metadata.names.join(', ')));
    return rows;
  }

  Widget _metadataRow(String label, String value) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: AppTheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textSecondary),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, provider, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('SMS Analysis'),
            actions: [
              IconButton(
                icon: Icon(
                  _selectedTab == 1 ? Icons.inbox : Icons.add_circle_outline,
                  color: AppTheme.primary,
                ),
                onPressed: () => setState(() => _selectedTab = _selectedTab == 0 ? 1 : 0),
              ),
            ],
          ),
          body: _selectedTab == 0 ? _buildInbox(provider) : _buildAddNew(),
        );
      },
    );
  }

  Widget _buildInbox(AppProvider provider) {
    final messages = provider.smsMessages;
    final status = provider.nativeSmsStatus;

    return Column(
      children: [
        if (NativeSmsBridge.isSupported)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                border: Border.all(color: AppTheme.outlineVariant),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.shield_outlined, color: AppTheme.primary, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'Native Android Detector',
                        style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.onSurface),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    status == null
                        ? 'Checking detector status...'
                        : status.modelAvailable
                            ? 'TinyBERT + rule engine ready for on-device SMS scanning.'
                            : 'Rule engine active. TinyBERT model/vocab not found yet, so native fallback is running locally.',
                    style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary, height: 1.4),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (status != null)
                        _infoPill(
                          status.hasSmsPermissions ? 'Permissions Granted' : 'Permissions Needed',
                          status.hasSmsPermissions ? AppTheme.secondary : AppTheme.warningOrange,
                        ),
                      if (status != null)
                        _infoPill(
                          status.modelAvailable ? 'TinyBERT Loaded' : 'Rule-Only Fallback',
                          status.modelAvailable ? AppTheme.primary : AppTheme.warningOrange,
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      if (status?.hasSmsPermissions != true)
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _isSyncing ? null : _requestPermissions,
                            icon: _isSyncing
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.onPrimary),
                                  )
                                : const Icon(Icons.lock_open_rounded, size: 18),
                            label: const Text('Grant SMS Access'),
                          ),
                        ),
                      if (status?.hasSmsPermissions == true) ...[
                        Expanded(
                          child: Text(
                            _isSyncing
                                ? 'Scanning device inbox...'
                                : 'Inbox scans automatically on open.',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: AppTheme.textSecondary,
                              height: 1.4,
                            ),
                          ),
                        ),
                        _isSyncing
                            ? const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 8),
                                child: SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppTheme.primary,
                                  ),
                                ),
                              )
                            : IconButton(
                                icon: const Icon(Icons.refresh_rounded, size: 20),
                                color: AppTheme.primary,
                                tooltip: 'Refresh inbox',
                                onPressed: _syncInbox,
                              ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        Expanded(
          child: messages.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.sms_outlined, size: 64, color: AppTheme.textLight),
                      const SizedBox(height: 16),
                      Text('No SMS messages', style: GoogleFonts.inter(color: AppTheme.textSecondary)),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: () => setState(() => _selectedTab = 1),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Add SMS'),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length,
                  itemBuilder: (ctx, i) {
                    final sms = messages[i];
                    final riskScore = (sms.localRiskScore * 100).round();
                    final riskColor = AppTheme.getRiskColor(riskScore);

                    return GestureDetector(
                      onTap: () => _showAnalysisDetail(sms),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        clipBehavior: Clip.hardEdge,
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                          border: Border.all(color: AppTheme.outlineVariant),
                        ),
                        child: IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Container(width: 3, color: riskColor),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                            Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: AppTheme.surfaceContainerHighest,
                                    border: Border.all(color: AppTheme.outlineVariant),
                                  ),
                                  child: Icon(
                                    riskScore >= 50 ? Icons.warning_rounded : Icons.check_circle,
                                    color: riskColor,
                                    size: 18,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        sms.sender,
                                        style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.onSurface),
                                      ),
                                      Text(
                                        '${sms.timestamp.hour}:${sms.timestamp.minute.toString().padLeft(2, '0')}',
                                        style: GoogleFonts.inter(fontSize: 11, color: AppTheme.onSurfaceVariant),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AppTheme.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                                    border: Border.all(color: riskColor),
                                  ),
                                  child: Text(
                                    '${(sms.localRiskScore * 100).round()}%',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: riskColor,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.flag_outlined, size: 18, color: AppTheme.danger),
                                  tooltip: 'Flag sender as spam',
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  onPressed: () => showFlagDialog(
                                    context,
                                    flaggedPhone: sms.sender,
                                    displayName: sms.sender,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              sms.body,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textSecondary, height: 1.4),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: [
                                _infoPill(sms.classification.replaceAll('_', ' '), AppTheme.primary),
                                if (sms.analysisSource.startsWith('android_'))
                                  _infoPill('Android Native', AppTheme.secondary),
                                if (sms.shouldEscalateToCloud)
                                  _infoPill('Cloud Fallback Pending', AppTheme.warningOrange),
                              ],
                            ),
                            if (sms.flags.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: sms.flags.take(3).map((f) => Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: AppTheme.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                                    border: Border.all(color: riskColor),
                                  ),
                                  child: Text(
                                    SmsDetector.getFlagDescription(f),
                                    style: GoogleFonts.inter(
                                      fontSize: 10,
                                      color: riskColor,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                )).toList(),
                              ),
                            ],
                            const SizedBox(height: 6),
                            Text(
                              'Tap to view local analysis →',
                              style: GoogleFonts.inter(fontSize: 11, color: AppTheme.primary, fontWeight: FontWeight.w500),
                            ),
                                  ],
                                ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildAddNew() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Simulate SMS Input',
            style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            'Manual input is analyzed locally. On Android it uses the native rule engine plus TinyBERT when the model is present.',
            style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 24),
          Text('Sender', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          TextField(
            controller: _senderController,
            decoration: const InputDecoration(
              hintText: 'Sender name or number',
              prefixIcon: Icon(Icons.person_outline),
            ),
          ),
          const SizedBox(height: 20),
          Text('Message', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          TextField(
            controller: _smsInputController,
            maxLines: 5,
            decoration: const InputDecoration(
              hintText: 'Enter SMS content here...',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Quick Templates',
            style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _templateChip('KYC Scam', 'URGENT: Your bank account has been BLOCKED due to KYC verification expired. Update KYC immediately: http://fake-bank.xyz/kyc'),
              _templateChip('Prize Scam', 'Congratulations!!! You WON Rs.50,00,000 LOTTERY! Send Rs.5000 to claim. Hurry, offer expires TODAY!'),
              _templateChip('OTP Scam', 'Dear Customer, Your SBI account will be suspended. Share your OTP and card details immediately to reactivate.'),
              _templateChip('Safe SMS', 'Your account XX1234 has been credited with Rs.1500.00. Available balance: Rs.45,250.00.'),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _isAnalyzing ? null : _addAndAnalyzeSms,
              icon: _isAnalyzing
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.onPrimary))
                  : const Icon(Icons.security_rounded, size: 20),
              label: Text(
                _isAnalyzing ? 'Analyzing...' : 'Analyze SMS Locally',
                style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _templateChip(String label, String text) {
    return GestureDetector(
      onTap: () => setState(() => _smsInputController.text = text),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          border: Border.all(color: AppTheme.outlineVariant),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: AppTheme.primary),
        ),
      ),
    );
  }
}
