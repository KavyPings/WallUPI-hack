/// UPI payment data parser
///
/// Handles:
///  - UPI deep-link format: upi://pay?pa=merchant@upi&pn=Name&am=500&cu=INR
///  - Plain UPI IDs: merchant@upi
///  - Phone numbers as UPI targets

class UpiPaymentData {
  /// Payee address (VPA) e.g. "claim@rewards"
  final String payeeAddress;

  /// Payee display name, empty if not present
  final String payeeName;

  /// Pre-filled amount (0 if not specified)
  final double amount;

  /// Currency (default INR)
  final String currency;

  /// True if parsed from a full deep-link (richer data)
  final bool fromDeepLink;

  const UpiPaymentData({
    required this.payeeAddress,
    this.payeeName = '',
    this.amount = 0,
    this.currency = 'INR',
    this.fromDeepLink = false,
  });

  bool get hasAmount => amount > 0;

  @override
  String toString() =>
      'UpiPaymentData(pa=$payeeAddress, pn=$payeeName, am=$amount, fromDeepLink=$fromDeepLink)';
}

class UpiParser {
  // UPI VPA pattern
  static final _vpaPattern = RegExp(r'^[\w.\-]+@[\w.\-]+$');

  // Indian mobile number (10 digits, 6-9 start)
  static final _phonePattern = RegExp(r'^(?:\+91|91)?([6-9]\d{9})$');

  /// Parse a raw QR string or UPI ID.
  ///
  /// Accepts:
  ///  - `upi://pay?pa=...&pn=...&am=...` (standard UPI QR)
  ///  - `merchant@upi` (plain VPA)
  ///  - `9876543210` (phone number, treated as payee address)
  ///
  /// Returns null if the input cannot be parsed as a valid UPI target.
  static UpiPaymentData? parse(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    // ── Deep-link format ─────────────────────────────────────────────────────
    if (trimmed.toLowerCase().startsWith('upi://')) {
      return _parseDeepLink(trimmed);
    }

    // ── Plain VPA ────────────────────────────────────────────────────────────
    if (_vpaPattern.hasMatch(trimmed)) {
      return UpiPaymentData(payeeAddress: trimmed.toLowerCase());
    }

    // ── Phone number ─────────────────────────────────────────────────────────
    final phoneMatch = _phonePattern.firstMatch(trimmed.replaceAll(RegExp(r'[\s\-]'), ''));
    if (phoneMatch != null) {
      return UpiPaymentData(payeeAddress: phoneMatch.group(1)!);
    }

    return null;
  }

  static UpiPaymentData? _parseDeepLink(String url) {
    try {
      // upi://pay?pa=x&pn=y&am=z&cu=INR  →  treat host+path as opaque, parse query
      // Uri.parse works if we normalise the scheme
      final uri = Uri.parse(url.replaceFirst('upi://', 'https://upi/'));
      final params = uri.queryParameters;

      final pa = params['pa']?.trim() ?? '';
      if (pa.isEmpty) return null;

      final pn = Uri.decodeComponent(params['pn'] ?? '').trim();
      final amStr = params['am']?.replaceAll(',', '') ?? '0';
      final am = double.tryParse(amStr) ?? 0;
      final cu = params['cu'] ?? 'INR';

      return UpiPaymentData(
        payeeAddress: pa.toLowerCase(),
        payeeName: pn,
        amount: am,
        currency: cu,
        fromDeepLink: true,
      );
    } catch (_) {
      return null;
    }
  }

  // ── Demo QR strings ────────────────────────────────────────────────────────
  // Used by the simulated QR scan flow. Each string is a real UPI deep-link
  // that the parser can process, matching entries in demo_data.dart.

  /// Safe QR — Swiggy food order
  static const demoSafeQr =
      'upi://pay?pa=swiggy@merchant&pn=Swiggy%20Food&am=289&cu=INR';

  /// Medium-risk QR — unknown recipient
  static const demoMediumQr =
      'upi://pay?pa=random12345@upi&pn=Unknown%20User&am=5000&cu=INR';

  /// HIGH-risk QR — matches the KYC scam SMS sender (SMS003, +91-9999888777)
  /// The SMS body mentions "kycupdate@upi" explicitly, so this will trigger correlation
  static const demoKycScamQr =
      'upi://pay?pa=kycupdate@upi&pn=KYC%20Helpdesk&am=99&cu=INR';

  /// CRITICAL QR — matches lottery SMS (SMS004) body which mentions "claim@rewards"
  static const demoLotteryScamQr =
      'upi://pay?pa=claim@rewards&pn=Rewards%20Desk&am=5000&cu=INR';

  static List<Map<String, String>> get demoQrOptions => [
    {'label': 'Safe — Swiggy Order', 'qr': demoSafeQr},
    {'label': 'Medium — Unknown Contact', 'qr': demoMediumQr},
    {'label': '⚠️ Suspicious — KYC Scam UPI', 'qr': demoKycScamQr},
    {'label': '🔴 Critical — Lottery Claim', 'qr': demoLotteryScamQr},
  ];
}
