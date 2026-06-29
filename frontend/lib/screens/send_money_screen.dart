import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../theme/app_theme.dart';
import '../providers/app_provider.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../services/risk_decision_engine.dart';
import '../services/upi_parser.dart';
import 'risk_warning_screen.dart';
import 'critical_delay_screen.dart';
import '../services/native_payment_bridge.dart';
import 'payment_success_screen.dart';
import 'qr_scanner_screen.dart';
import 'offline_payment_helper.dart';

class SendMoneyScreen extends StatefulWidget {
  final bool triggeredByQr;
  final String? prefilledUpiId;
  final double? prefilledAmount;
  final PaymentIntentEvent? paymentIntent;

  const SendMoneyScreen({
    super.key,
    this.triggeredByQr = false,
    this.prefilledUpiId,
    this.prefilledAmount,
    this.paymentIntent,
  });

  @override
  State<SendMoneyScreen> createState() => _SendMoneyScreenState();
}

class _SendMoneyScreenState extends State<SendMoneyScreen> {
  final _upiController = TextEditingController();
  final _noteController = TextEditingController();
  final _amountController = TextEditingController(); // used by risk engine

  bool _isChecking = false;
  int _currentRiskScore = 0;
  String? _recipientName;
  int _recipientFlagCount = 0;

  // Two-step flow: 0 = recipient entry, 1 = amount entry
  int _step = 0;
  String _amountDisplay = '0';

  SmsMessage? _activeSms;
  List<SmsMessage> _flaggedSms = [];
  PaymentIntentEvent? _activePaymentIntent;

  @override
  void initState() {
    super.initState();
    _activePaymentIntent = widget.paymentIntent;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final provider = context.read<AppProvider>();
      setState(() { _flaggedSms = provider.flaggedSms; });
      provider.addListener(_onProviderChanged);

      if (_activePaymentIntent != null) {
        final details = _activePaymentIntent!.details;
        _upiController.text = details.payeeAddress;
        if (details.amount > 0) {
          final amt = details.amount.toStringAsFixed(0);
          _amountController.text = amt;
          _amountDisplay = amt;
        }
        if (details.transactionNote.isNotEmpty) {
          _noteController.text = details.transactionNote;
        }
        _recipientName = details.payeeName.isNotEmpty ? details.payeeName : null;
        _step = 1;
        _onRecipientChanged(details.payeeAddress);
      } else {
        if (widget.prefilledUpiId != null) {
          _upiController.text = widget.prefilledUpiId!;
          _onRecipientChanged(widget.prefilledUpiId!);
        }
        if (widget.prefilledAmount != null) {
          final amt = widget.prefilledAmount!.toStringAsFixed(0);
          _amountController.text = amt;
          _amountDisplay = amt;
        }
        // QR-triggered: auto-advance to amount step after brief lookup
        if (widget.triggeredByQr && widget.prefilledUpiId != null) {
          Future.delayed(const Duration(milliseconds: 350), () {
            if (mounted) setState(() => _step = 1);
          });
        }
      }
    });
    _upiController.addListener(_onUpiChanged);
  }

  void _onProviderChanged() {
    if (!mounted) return;
    final newFlagged = context.read<AppProvider>().flaggedSms;
    if (newFlagged.length != _flaggedSms.length) {
      setState(() { _flaggedSms = newFlagged; });
      _onRecipientChanged(_upiController.text.trim());
    }
  }

  @override
  void dispose() {
    if (mounted) {
      try { context.read<AppProvider>().removeListener(_onProviderChanged); } catch (_) {}
    }
    _upiController.removeListener(_onUpiChanged);
    _upiController.dispose();
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _onUpiChanged() => _onRecipientChanged(_upiController.text.trim());

  void _onRecipientChanged(String input) {
    final provider = context.read<AppProvider>();
    final recipient = provider.findRecipient(input);

    SmsMessage? matched;
    if (input.length >= 5 && _flaggedSms.isNotEmpty) {
      final lowerInput = input.toLowerCase();
      final inputClean = lowerInput.replaceAll(RegExp(r'[\s\-+]'), '');

      for (final sms in _flaggedSms) {
        final senderClean = sms.sender.toLowerCase().replaceAll(RegExp(r'[\s\-+]'), '');
        if (senderClean.isNotEmpty &&
            (senderClean == inputClean || senderClean.contains(inputClean) || inputClean.contains(senderClean))) {
          matched = sms; break;
        }
        final meta = sms.extractedMetadata;
        if (meta != null) {
          for (final upi in meta.upiIds) {
            if (upi == lowerInput || upi.contains(lowerInput) || lowerInput.contains(upi)) { matched = sms; break; }
          }
          if (matched != null) break;
          for (final phone in meta.phones) {
            if (phone == inputClean || phone.contains(inputClean) || inputClean.contains(phone)) { matched = sms; break; }
          }
          if (matched != null) break;
        }
        final smsBody = sms.body.toLowerCase();
        if (smsBody.contains(inputClean)) { matched = sms; break; }
        if (lowerInput.contains('@')) {
          final handle = lowerInput.split('@').first;
          if (handle.length > 2 && smsBody.contains(handle)) { matched = sms; break; }
        }
        if (recipient != null) {
          final nameParts = recipient.name.toLowerCase().split(' ').where((w) => w.length > 3);
          for (final part in nameParts) {
            if (smsBody.contains(part)) { matched = sms; break; }
          }
          if (matched != null) break;
        }
      }
    }

    setState(() {
      _recipientName = recipient?.name;
      _activeSms = matched;
      if (recipient == null) _recipientFlagCount = 0;
    });

    if (input.length >= 5) {
      _checkRecipientFlags(input);
    } else {
      setState(() => _recipientFlagCount = 0);
    }
  }

  Future<void> _checkRecipientFlags(String upiId) async {
    final count = await ApiService.checkSpamFlags(upiId);
    if (mounted) setState(() => _recipientFlagCount = count);
  }

  void _confirmRecipient() {
    final input = _upiController.text.trim();
    if (input.isEmpty) return;

    // Validate UPI ID format
    final atIndex = input.indexOf('@');
    final localPart = atIndex >= 0 ? input.substring(0, atIndex) : input;
    final isPhoneNumber = RegExp(r'^\d+$').hasMatch(localPart);
    if (isPhoneNumber && localPart.length != 10) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Phone number must be exactly 10 digits', style: GoogleFonts.inter()),
        backgroundColor: AppTheme.danger,
      ));
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() { _step = 1; _amountDisplay = '0'; _amountController.text = ''; });
  }

  // ── Numpad logic ──
  void _numpadAppend(String digit) {
    setState(() {
      if (_amountDisplay == '0') {
        _amountDisplay = digit;
      } else {
        if (_amountDisplay.contains('.') && _amountDisplay.split('.')[1].length >= 2) return;
        if (_amountDisplay.length < 8) _amountDisplay += digit;
      }
      _amountController.text = _amountDisplay == '0' ? '' : _amountDisplay;
    });
  }

  void _numpadDecimal() {
    setState(() {
      if (!_amountDisplay.contains('.')) _amountDisplay += '.';
    });
  }

  void _numpadDelete() {
    setState(() {
      if (_amountDisplay.length > 1) {
        _amountDisplay = _amountDisplay.substring(0, _amountDisplay.length - 1);
      } else {
        _amountDisplay = '0';
      }
      _amountController.text = _amountDisplay == '0' ? '' : _amountDisplay;
    });
  }

  // ── QR / Camera ──
  Future<void> _handleQrScan() async {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
        side: BorderSide(color: AppTheme.outlineVariant),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 36, height: 4, decoration: BoxDecoration(color: AppTheme.outlineVariant, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 20),
            Text('Scan QR Code', style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w600, color: AppTheme.onSurface)),
            const SizedBox(height: 8),
            _qrOption(ctx, Icons.camera_alt_rounded, AppTheme.primary, 'Scan with Camera', 'Use your camera to scan a QR code', _openCameraScanner),
            const Divider(height: 1, color: AppTheme.outlineVariant),
            _qrOption(ctx, Icons.photo_library_rounded, AppTheme.secondary, 'Upload QR Image', 'Pick a QR code image from gallery', _uploadQrImage),
            const Divider(height: 1, color: AppTheme.outlineVariant),
            _qrOption(ctx, Icons.edit_rounded, AppTheme.onSurfaceVariant, 'Enter Manually', 'Type UPI ID directly', () {}),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _qrOption(BuildContext ctx, IconData icon, Color color, String title, String sub, VoidCallback onTap) {
    return ListTile(
      leading: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          color: AppTheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          border: Border.all(color: AppTheme.outlineVariant),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(title, style: GoogleFonts.inter(fontWeight: FontWeight.w500, color: AppTheme.onSurface)),
      subtitle: Text(sub, style: GoogleFonts.inter(fontSize: 12, color: AppTheme.onSurfaceVariant)),
      trailing: const Icon(Icons.chevron_right, color: AppTheme.onSurfaceVariant, size: 18),
      onTap: () { Navigator.pop(ctx); onTap(); },
    );
  }

  Future<void> _openCameraScanner() async {
    final raw = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const QrScannerScreen()));
    if (raw == null || !mounted) return;
    final data = UpiParser.parse(raw);
    if (data == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not read QR code', style: GoogleFonts.inter()), backgroundColor: AppTheme.warningOrange));
      return;
    }
    setState(() {
      _upiController.text = data.payeeAddress;
      if (data.hasAmount) { final a = data.amount.toStringAsFixed(0); _amountController.text = a; _amountDisplay = a; }
      _step = 1;
    });
    _onRecipientChanged(data.payeeAddress);
    if (data.payeeName.isNotEmpty) setState(() => _recipientName = data.payeeName);
  }

  Future<void> _uploadQrImage() async {
    final image = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (!mounted || image == null) return;
    final controller = MobileScannerController();
    final completer = Completer<String?>();
    final sub = controller.barcodes.listen(
      (capture) { if (!completer.isCompleted) completer.complete(capture.barcodes.firstOrNull?.rawValue); },
      onError: (_) { if (!completer.isCompleted) completer.complete(null); },
    );
    final found = await controller.analyzeImage(image.path);
    if (!found && !completer.isCompleted) completer.complete(null);
    final raw = await completer.future;
    await sub.cancel();
    controller.dispose();
    if (!mounted) return;
    if (raw == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No QR code found in image', style: GoogleFonts.inter()), backgroundColor: AppTheme.warningOrange));
      return;
    }
    final data = UpiParser.parse(raw);
    if (data == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('QR code is not a valid UPI code', style: GoogleFonts.inter()), backgroundColor: AppTheme.warningOrange));
      return;
    }
    setState(() {
      _upiController.text = data.payeeAddress;
      if (data.hasAmount) { final a = data.amount.toStringAsFixed(0); _amountController.text = a; _amountDisplay = a; }
      _step = 1;
    });
    _onRecipientChanged(data.payeeAddress);
    if (data.payeeName.isNotEmpty) setState(() => _recipientName = data.payeeName);
  }

  // ── Risk & payment ──
  Future<void> _checkRiskAndPay() async {
    final upiId = _upiController.text.trim();
    final amountText = _amountController.text.trim();
    if (upiId.isEmpty || amountText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Please enter a valid amount', style: GoogleFonts.inter()), backgroundColor: AppTheme.danger));
      return;
    }
    final amount = double.tryParse(amountText);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Please enter a valid amount', style: GoogleFonts.inter()), backgroundColor: AppTheme.danger));
      return;
    }
    final user = context.read<AppProvider>().user;
    if (!(user?.isAdmin ?? false) && amount > (user?.balance ?? 0)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          'Insufficient balance — available ₹${NumberFormat('#,##,###').format(user?.balance ?? 0)}',
          style: GoogleFonts.inter(),
        ),
        backgroundColor: AppTheme.danger,
      ));
      return;
    }
    setState(() => _isChecking = true);
    final provider = context.read<AppProvider>();
    final session = await provider.checkRisk(
      amount: amount, recipientUpiId: upiId, recipientName: _recipientName ?? upiId,
      note: _noteController.text, triggeredByQr: widget.triggeredByQr, matchedSms: _activeSms,
      paymentIntent: _activePaymentIntent,
    );
    setState(() { _isChecking = false; _currentRiskScore = session?.result.score ?? 0; });
    if (!mounted) return;
    if (session == null) { _proceedWithPayment(0); return; }
    switch (session.level) {
      case RiskLevel.safe:
        _proceedWithPayment(session.result.score);
        break;
      case RiskLevel.soft:
        _showSoftWarningSheet(session);
        break;
      case RiskLevel.strong:
        final result = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => CriticalDelayScreen(session: session)));
        if (result != true) { provider.clearRiskSession(); setState(() => _currentRiskScore = 0); }
        break;
      case RiskLevel.critical:
        final result = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => RiskWarningScreen(session: session)));
        if (result != true) { provider.clearRiskSession(); setState(() => _currentRiskScore = 0); }
        break;
    }
  }

  void _showSoftWarningSheet(RiskSessionContext session) {
    final score = session.result.score;
    final riskColor = AppTheme.getRiskColor(score);
    bool proceeded = false;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: AppTheme.surfaceContainerLow,
          borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
          border: Border(top: BorderSide(color: AppTheme.outlineVariant)),
        ),
        padding: EdgeInsets.fromLTRB(24, 16, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: AppTheme.divider, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 20),
            Row(children: [
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(color: AppTheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(AppTheme.radiusMedium), border: Border.all(color: riskColor)),
                child: Icon(Icons.warning_amber_rounded, color: riskColor, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Caution Advised', style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w700, color: riskColor)),
                Text('Risk score: $score/100 — ${RiskDecisionEngine.levelLabel(session.level)}', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.onSurfaceVariant)),
              ])),
            ]),
            const SizedBox(height: 16),
            Container(
              width: double.infinity, padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: AppTheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(AppTheme.radiusMedium), border: Border.all(color: AppTheme.outlineVariant)),
              child: Text(session.result.interventionMessage, style: GoogleFonts.inter(fontSize: 13, color: AppTheme.onSurface)),
            ),
            const SizedBox(height: 12),
            ...session.result.factors.take(3).map((f) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                Container(width: 7, height: 7, decoration: BoxDecoration(
                  color: f.severity == 'high' ? AppTheme.danger : f.severity == 'medium' ? AppTheme.warningOrange : AppTheme.riskMedium,
                  shape: BoxShape.circle,
                )),
                const SizedBox(width: 10),
                Expanded(child: Text(f.factor, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: AppTheme.onSurface))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(color: AppTheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(AppTheme.radiusSmall), border: Border.all(color: f.severity == 'high' ? AppTheme.danger : AppTheme.warningOrange)),
                  child: Text('+${f.contribution}', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: f.severity == 'high' ? AppTheme.danger : AppTheme.warningOrange)),
                ),
              ]),
            )),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(child: OutlinedButton(
                onPressed: () { Navigator.pop(ctx); context.read<AppProvider>().clearRiskSession(); setState(() => _currentRiskScore = 0); },
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), side: const BorderSide(color: AppTheme.outlineVariant), foregroundColor: AppTheme.onSurface, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusSmall))),
                child: Text('Cancel', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
              )),
              const SizedBox(width: 12),
              Expanded(child: ElevatedButton(
                onPressed: () { proceeded = true; Navigator.pop(ctx); _proceedWithPayment(score); },
                style: ElevatedButton.styleFrom(backgroundColor: riskColor, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14), elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusSmall))),
                child: Text('Proceed Anyway', style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: Colors.white)),
              )),
            ]),
          ],
        ),
      ),
    ).whenComplete(() {
      if (proceeded) return;
      if (!mounted) return;
      final provider = context.read<AppProvider>();
      if (provider.currentRiskSession != null) { provider.clearRiskSession(); setState(() => _currentRiskScore = 0); }
    });
  }

  void _proceedWithPayment(int riskScore) async {
    final provider = context.read<AppProvider>();
    final upiId = _upiController.text.trim();
    final amount = double.parse(_amountController.text.trim());

    if (provider.currentRiskSession?.isOffline == true) {
      showOfflinePaymentPicker(
        context,
        amount: amount,
        recipientName: _recipientName ?? upiId,
        recipientUpiId: upiId,
        riskScore: riskScore,
        note: _noteController.text,
        wasCorrelatedWithSms: _activeSms != null,
      );
      return;
    }

    await provider.processPayment(
      recipientName: _recipientName ?? upiId, recipientUpiId: upiId,
      amount: amount, note: _noteController.text, riskScore: riskScore,
      wasCorrelatedWithSms: _activeSms != null,
    );
    if (!mounted) return;
    Navigator.pushReplacement(context, MaterialPageRoute(
      builder: (_) => PaymentSuccessScreen(amount: amount, recipientName: _recipientName ?? upiId, recipientUpiId: upiId, riskScore: riskScore),
    ));
  }

  // ────────────────────────────────────────────────────────────────
  // BUILD
  // ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: _step == 0 ? _buildRecipientStep() : _buildAmountStep(),
      ),
    );
  }

  // ── Shared header ──
  Widget _buildHeader({required bool showBack}) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(bottom: BorderSide(color: AppTheme.outlineVariant)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(showBack ? Icons.arrow_back : Icons.close, color: AppTheme.onSurface, size: 22),
            onPressed: showBack
                ? () => setState(() { _step = 0; _currentRiskScore = 0; })
                : () => Navigator.pop(context),
          ),
          Expanded(
            child: Text(
              widget.triggeredByQr ? 'QR Payment' : 'Send Money',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w600, color: AppTheme.onSurface, letterSpacing: -0.3),
            ),
          ),
          if (!showBack)
            IconButton(
              icon: const Icon(Icons.qr_code_scanner_rounded, color: AppTheme.primary, size: 22),
              onPressed: _handleQrScan,
            )
          else if (_activeSms != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                  border: Border.all(color: AppTheme.danger),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.warning_rounded, color: AppTheme.danger, size: 13),
                  const SizedBox(width: 3),
                  Text('SMS', style: GoogleFonts.inter(fontSize: 10, color: AppTheme.danger, fontWeight: FontWeight.w600)),
                ]),
              ),
            )
          else
            const SizedBox(width: 48),
        ],
      ),
    );
  }

  // ── STEP 0: Recipient entry ──
  Widget _buildRecipientStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(showBack: false),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 40, 24, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Who are you paying?',
                    style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w600, color: AppTheme.onSurface, letterSpacing: -0.4)),
                const SizedBox(height: 6),
                Text('Enter UPI ID or phone number',
                    style: GoogleFonts.inter(fontSize: 14, color: AppTheme.outline)),
                const SizedBox(height: 32),

                // UPI input
                TextField(
                  controller: _upiController,
                  autofocus: true,
                  style: GoogleFonts.inter(fontSize: 16, color: AppTheme.onSurface),
                  decoration: InputDecoration(
                    hintText: 'name@bank or 10-digit number',
                    prefixIcon: const Icon(Icons.alternate_email, size: 20),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.qr_code_scanner, color: AppTheme.primary),
                      onPressed: _handleQrScan,
                    ),
                  ),
                  onChanged: _onRecipientChanged,
                ),

                // Recipient confirmed chip
                if (_recipientName != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                      border: Border.all(color: AppTheme.outlineVariant),
                    ),
                    child: Row(children: [
                      Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppTheme.surfaceContainerHighest,
                          border: Border.all(color: AppTheme.outlineVariant),
                        ),
                        child: Center(child: Text(
                          _recipientName!.isNotEmpty ? _recipientName![0].toUpperCase() : '?',
                          style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600, color: AppTheme.onSurface),
                        )),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(_recipientName!, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500, color: AppTheme.onSurface)),
                        Text(_upiController.text.trim(), style: GoogleFonts.inter(fontSize: 12, color: AppTheme.outline, letterSpacing: 0.2)),
                      ])),
                      const Icon(Icons.check_circle_rounded, color: AppTheme.riskSafe, size: 18),
                    ]),
                  ),
                ],

                // Flag count warning
                if (_recipientFlagCount > 0) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                      border: Border.all(color: AppTheme.warningOrange),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.flag_rounded, color: AppTheme.warningOrange, size: 14),
                      const SizedBox(width: 6),
                      Text(
                        'Flagged by $_recipientFlagCount user${_recipientFlagCount == 1 ? '' : 's'} as suspicious',
                        style: GoogleFonts.inter(fontSize: 12, color: AppTheme.warningOrange, fontWeight: FontWeight.w500),
                      ),
                    ]),
                  ),
                ],

                // SMS match banner
                if (_activeSms != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    clipBehavior: Clip.hardEdge,
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                      border: Border.all(color: AppTheme.outlineVariant),
                    ),
                    child: IntrinsicHeight(
                      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Container(width: 3, color: AppTheme.danger),
                        Expanded(child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              const Icon(Icons.warning_rounded, size: 16, color: AppTheme.danger),
                              const SizedBox(width: 6),
                              Expanded(child: Text('⚠️ Suspicious SMS linked to this recipient!',
                                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.danger))),
                            ]),
                            const SizedBox(height: 6),
                            Text(_activeSms!.body, maxLines: 2, overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary)),
                            const SizedBox(height: 4),
                            Text(
                              'Risk: ${(_activeSms!.localRiskScore * 100).round()}%  •  From: ${_activeSms!.sender}',
                              style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.danger),
                            ),
                          ]),
                        )),
                      ]),
                    ),
                  ),
                ],

                const SizedBox(height: 40),

                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _upiController.text.trim().length >= 5 ? _confirmRecipient : null,
                    child: Text('Continue', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── STEP 1: Amount entry (Aura Pay layout) ──
  Widget _buildAmountStep() {
    final amountValue = double.tryParse(_amountDisplay) ?? 0;
    final canPay = amountValue > 0 && !_isChecking;
    final displayName = _recipientName ?? _upiController.text.trim();
    final initial = displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';

    return Column(
      children: [
        _buildHeader(showBack: true),

        // Recipient identity — centered
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
          child: Column(
            children: [
              Container(
                width: 60, height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.surfaceContainerHighest,
                  border: Border.all(color: AppTheme.outlineVariant),
                  boxShadow: const [AppTheme.innerHighlight],
                ),
                child: Center(child: Text(initial, style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w600, color: AppTheme.onSurface))),
              ),
              const SizedBox(height: 8),
              Text(displayName, style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w500, color: AppTheme.onSurface)),
              const SizedBox(height: 2),
              Text('@${_upiController.text.trim()}', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.outline, letterSpacing: 0.2)),
              if (_recipientFlagCount > 0) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(color: AppTheme.warningOrange),
                  ),
                  child: Text('⚠️ Flagged by $_recipientFlagCount user${_recipientFlagCount == 1 ? '' : 's'}',
                      style: GoogleFonts.inter(fontSize: 11, color: AppTheme.warningOrange, fontWeight: FontWeight.w500)),
                ),
              ],
              if (_activePaymentIntent != null) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(color: _activePaymentIntent!.risk.score >= 80 ? AppTheme.danger : AppTheme.outlineVariant),
                  ),
                  child: Text('Source: ${_activePaymentIntent!.details.referrerAppLabel}',
                      style: GoogleFonts.inter(fontSize: 11, color: _activePaymentIntent!.risk.score >= 80 ? AppTheme.danger : AppTheme.onSurfaceVariant, fontWeight: FontWeight.w500)),
                ),
              ],
            ],
          ),
        ),

        // Amount display — flexible center
        Expanded(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text('₹', style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.w500, color: AppTheme.outline)),
                    ),
                    const SizedBox(width: 2),
                    Text(
                      _amountDisplay,
                      style: GoogleFonts.inter(fontSize: 52, fontWeight: FontWeight.w600, color: AppTheme.onSurface, letterSpacing: -2),
                    ),
                  ],
                ),
                if (_currentRiskScore > 0) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(100),
                      border: Border.all(color: AppTheme.getRiskColor(_currentRiskScore)),
                    ),
                    child: Text(
                      'Risk: $_currentRiskScore% — ${AppTheme.getRiskLabel(_currentRiskScore)}',
                      style: GoogleFonts.inter(fontSize: 12, color: AppTheme.getRiskColor(_currentRiskScore), fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Consumer<AppProvider>(
                  builder: (_, p, __) {
                    final balance = p.user?.balance ?? 0;
                    final isOver = !(p.user?.isAdmin ?? false) && amountValue > balance;
                    return Text(
                      'Available: ₹${NumberFormat('#,##,###').format(balance)}',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: isOver ? AppTheme.danger : AppTheme.outline,
                        fontWeight: isOver ? FontWeight.w600 : FontWeight.normal,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),

        // Note field — underline style
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 0, 32, 0),
          child: Row(
            children: [
              const Icon(Icons.edit_outlined, size: 18, color: AppTheme.outline),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _noteController,
                  style: GoogleFonts.inter(fontSize: 15, color: AppTheme.onSurface),
                  decoration: InputDecoration(
                    hintText: 'Add a note...',
                    hintStyle: GoogleFonts.inter(fontSize: 15, color: AppTheme.outline),
                    filled: false,
                    border: const UnderlineInputBorder(borderSide: BorderSide(color: AppTheme.outlineVariant)),
                    enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: AppTheme.outlineVariant)),
                    focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppTheme.primary, width: 1.5)),
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 10),

        // SMS alert banner (compact, only when matched)
        if (_activeSms != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Container(
              clipBehavior: Clip.hardEdge,
              decoration: BoxDecoration(
                color: AppTheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                border: Border.all(color: AppTheme.outlineVariant),
              ),
              child: IntrinsicHeight(
                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Container(width: 3, color: AppTheme.danger),
                  Expanded(child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(children: [
                      const Icon(Icons.warning_rounded, size: 14, color: AppTheme.danger),
                      const SizedBox(width: 6),
                      Expanded(child: Text('⚠️ Suspicious SMS matches this recipient',
                          style: GoogleFonts.inter(fontSize: 12, color: AppTheme.danger, fontWeight: FontWeight.w500))),
                    ]),
                  )),
                ]),
              ),
            ),
          ),

        // Keypad panel
        Container(
          decoration: const BoxDecoration(
            color: AppTheme.surfaceContainerLow,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            border: Border(top: BorderSide(color: AppTheme.outlineVariant, width: 0.5)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            children: [
              // 4 rows of numpad
              for (final row in [['1','2','3'], ['4','5','6'], ['7','8','9'], ['.','0','⌫']])
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: row.map((key) => Expanded(
                      child: _NumpadBtn(
                        label: key,
                        onTap: () {
                          if (key == '⌫') {
                            _numpadDelete();
                          } else if (key == '.') {
                            _numpadDecimal();
                          } else {
                            _numpadAppend(key);
                          }
                        },
                      ),
                    )).toList(),
                  ),
                ),
              const SizedBox(height: 12),

              // Review Transfer button — pill shaped, cobalt
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: canPay ? _checkRiskAndPay : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accent,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shadowColor: Colors.transparent,
                    shape: const StadiumBorder(),
                    disabledBackgroundColor: AppTheme.surfaceContainerHigh,
                    disabledForegroundColor: AppTheme.outline,
                  ),
                  child: _isChecking
                      ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                          const SizedBox(width: 12),
                          Text('Checking Risk...', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600)),
                        ])
                      : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          const Icon(Icons.shield_outlined, size: 18),
                          const SizedBox(width: 8),
                          Text('Review Transfer', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600)),
                        ]),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Numpad button ──
class _NumpadBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _NumpadBtn({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(100),
      splashColor: AppTheme.surfaceContainerHighest,
      highlightColor: AppTheme.surfaceContainerHigh,
      child: SizedBox(
        height: 54,
        child: Center(
          child: label == '⌫'
              ? const Icon(Icons.backspace_outlined, size: 22, color: AppTheme.onSurfaceVariant)
              : Text(label, style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.w500, color: AppTheme.onSurface)),
        ),
      ),
    );
  }
}
