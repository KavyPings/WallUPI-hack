import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import '../theme/app_theme.dart';
import '../providers/app_provider.dart';
import '../services/api_service.dart';
import '../services/native_sms_bridge.dart';
import '../widgets/ai_status_pill.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _phoneController = TextEditingController();
  final _nameController = TextEditingController();
  final _otpController = TextEditingController();

  bool _otpSent = false;
  bool _isLoading = false;
  bool _isAdminPhone = false;

  // null = checking, true = on, false = off
  bool? _cloudOn;
  bool? _tinyBertOn;

  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));
    _animController.forward();
    _phoneController.addListener(_onPhoneChanged);
  }

  void _onPhoneChanged() {
    final isAdmin = _phoneController.text.trim() == '0000000000';
    if (isAdmin != _isAdminPhone) {
      setState(() => _isAdminPhone = isAdmin);
      if (isAdmin) _checkAiStatus();
    }
  }

  Future<void> _checkAiStatus() async {
    if (!mounted) return;
    setState(() { _cloudOn = null; _tinyBertOn = null; });

    // Cloud AI — probe the backend /status endpoint
    try {
      final response = await http
          .get(Uri.parse('${ApiService.baseUrl}/status'),
               headers: {'ngrok-skip-browser-warning': 'true'})
          .timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (mounted) {
          setState(() => _cloudOn =
              (data['cloud_configured'] ?? data['gemini_configured']) == true);
        }
      } else {
        if (mounted) setState(() => _cloudOn = false);
      }
    } catch (_) {
      if (mounted) setState(() => _cloudOn = false);
    }

    // TinyBERT — query the native Android SMS detector
    try {
      final status = await NativeSmsBridge.getDetectorStatus();
      if (mounted) setState(() => _tinyBertOn = status?.modelAvailable ?? false);
    } catch (_) {
      if (mounted) setState(() => _tinyBertOn = false);
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    _phoneController.removeListener(_onPhoneChanged);
    _phoneController.dispose();
    _nameController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    final phone = _phoneController.text.trim();
    final name = _nameController.text.trim();
    if (phone.length != 10 || !RegExp(r'^\d{10}$').hasMatch(phone)) {
      _showError('Enter a valid 10-digit mobile number'); return;
    }
    if (name.isEmpty) { _showError('Please enter your name'); return; }
    if (phone == '0000000000' && name.toLowerCase() != 'kavy') {
      _showError('Invalid admin credentials'); return;
    }

    // Admin bypass — skip backend
    if (phone == '0000000000') {
      setState(() { _otpSent = true; _otpController.clear(); });
      return;
    }

    setState(() => _isLoading = true);
    try {
      final resp = await http.post(
        Uri.parse('${ApiService.baseUrl}/otp/send'),
        headers: {'Content-Type': 'application/json', 'ngrok-skip-browser-warning': 'true'},
        body: jsonEncode({'phone': phone}),
      ).timeout(const Duration(seconds: 15));

      if (!mounted) return;
      if (resp.statusCode == 200) {
        setState(() { _otpSent = true; _isLoading = false; _otpController.clear(); });
      } else {
        final msg = (jsonDecode(resp.body) as Map)['error'] ?? 'Failed to send OTP';
        setState(() => _isLoading = false);
        _showError(msg.toString());
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showError('Could not reach server. Check your connection.');
    }
  }

  Future<void> _verifyOtp() async {
    final phone = _phoneController.text.trim();
    final otp = _otpController.text.trim();
    if (otp.length != 6) { _showError('Enter the 6-digit OTP'); return; }

    // Admin bypass
    if (phone == '0000000000') {
      if (otp != '123456') { _showError('Invalid admin OTP. Use 123456.'); return; }
      setState(() => _isLoading = true);
      await Future.delayed(const Duration(milliseconds: 400));
      if (!mounted) return;
      final provider = context.read<AppProvider>();
      await provider.login(_nameController.text.trim(), phone);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const HomeScreen()));
      return;
    }

    setState(() => _isLoading = true);
    try {
      final resp = await http.post(
        Uri.parse('${ApiService.baseUrl}/otp/verify'),
        headers: {'Content-Type': 'application/json', 'ngrok-skip-browser-warning': 'true'},
        body: jsonEncode({'phone': phone, 'otp': otp}),
      ).timeout(const Duration(seconds: 10));

      if (!mounted) return;
      if (resp.statusCode == 200) {
        final provider = context.read<AppProvider>();
        await provider.login(_nameController.text.trim(), phone);
        if (!mounted) return;
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const HomeScreen()));
      } else {
        final msg = (jsonDecode(resp.body) as Map)['error'] ?? 'Invalid OTP';
        setState(() => _isLoading = false);
        _showError(msg.toString());
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showError('Could not reach server. Check your connection.');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.inter()),
        backgroundColor: AppTheme.danger,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: SlideTransition(
            position: _slideAnim,
            child: SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: MediaQuery.of(context).size.height -
                      MediaQuery.of(context).padding.top -
                      MediaQuery.of(context).padding.bottom,
                ),
                child: IntrinsicHeight(
                  child: Column(
                    children: [
                      // ── Top branding section ──
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 48, 20, 0),
                        child: Column(
                          children: [
                            // Logo
                            _buildLogo(),
                            const SizedBox(height: 20),
                            // App name
                            Text(
                              'WALLUPI',
                              style: GoogleFonts.inter(
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.onSurface,
                                letterSpacing: 6,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'SAFE PAYMENTS. SMART PROTECTION.',
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                                color: AppTheme.outline,
                                letterSpacing: 2.5,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 48),

                      // ── Form section ──
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: _otpSent ? _buildOtpStep() : _buildDetailsStep(),
                      ),

                      const Spacer(),

                      // ── Footer ──
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.shield_outlined, size: 12, color: AppTheme.outline),
                                const SizedBox(width: 6),
                                Text(
                                  'Protected by Wallupi AI',
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    color: AppTheme.outline,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Mock app — No real banking integration',
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                color: AppTheme.outlineVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        color: AppTheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.outlineVariant),
        boxShadow: const [AppTheme.innerHighlight],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(19),
        child: Image.asset(
          'assets/images/logo.png',
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const Center(
            child: Icon(Icons.shield_rounded, size: 40, color: AppTheme.onSurface),
          ),
        ),
      ),
    );
  }

  Widget _buildDetailsStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Create Account',
          style: GoogleFonts.inter(
            fontSize: 22, fontWeight: FontWeight.w600,
            color: AppTheme.onSurface, letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Enter your details to get started',
          style: GoogleFonts.inter(fontSize: 14, color: AppTheme.outline),
        ),
        const SizedBox(height: 28),

        // Name
        _fieldLabel('Your Name'),
        const SizedBox(height: 8),
        TextField(
          controller: _nameController,
          textCapitalization: TextCapitalization.words,
          style: GoogleFonts.inter(fontSize: 16, color: AppTheme.onSurface),
          decoration: InputDecoration(
            hintText: 'Enter your full name',
            prefixIcon: const Icon(Icons.person_outline, size: 18),
          ),
          onSubmitted: (_) => FocusScope.of(context).nextFocus(),
        ),
        const SizedBox(height: 20),

        // Phone
        _fieldLabel('Mobile Number'),
        const SizedBox(height: 8),
        TextField(
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          maxLength: 10,
          style: GoogleFonts.inter(fontSize: 16, color: AppTheme.onSurface, letterSpacing: 1),
          decoration: InputDecoration(
            hintText: '10-digit mobile number',
            prefixIcon: const Icon(Icons.phone_outlined, size: 18),
            prefixText: '+91  ',
            prefixStyle: GoogleFonts.inter(color: AppTheme.outline, fontSize: 14),
            counterText: '',
          ),
        ),

        if (_isAdminPhone) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: AppTheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
              border: Border.all(color: AppTheme.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.admin_panel_settings, size: 15, color: AppTheme.primary),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Admin login — enter name "Kavy"',
                        style: GoogleFonts.inter(fontSize: 12, color: AppTheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AiStatusPill(label: 'Cloud AI', isOn: _cloudOn),
                    const SizedBox(width: 6),
                    AiStatusPill(label: 'TinyBERT', isOn: _tinyBertOn),
                  ],
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _sendOtp,
            child: _isLoading
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.onPrimary))
                : Text('Send OTP', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600)),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.hourglass_empty_rounded, size: 13, color: AppTheme.outline),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                'First login can take ~15s while the server wakes up. '
                'If the first attempt fails, just tap Send OTP again.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 11, color: AppTheme.outline, height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildOtpStep() {
    final isAdmin = _phoneController.text.trim() == '0000000000';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // User identity card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
            border: Border.all(color: AppTheme.outlineVariant),
            boxShadow: const [AppTheme.innerHighlight],
          ),
          child: Row(
            children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                  border: Border.all(color: AppTheme.outlineVariant),
                ),
                child: Center(
                  child: Text(
                    _nameController.text.trim().isNotEmpty
                        ? _nameController.text.trim()[0].toUpperCase()
                        : '?',
                    style: GoogleFonts.inter(
                      fontSize: 18, fontWeight: FontWeight.w700,
                      color: AppTheme.onSurface,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          _nameController.text.trim(),
                          style: GoogleFonts.inter(
                            fontSize: 15, fontWeight: FontWeight.w600,
                            color: AppTheme.onSurface,
                          ),
                        ),
                        if (isAdmin) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppTheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: AppTheme.outlineVariant),
                            ),
                            child: Text(
                              'ADMIN',
                              style: GoogleFonts.inter(
                                fontSize: 9, fontWeight: FontWeight.w700,
                                color: AppTheme.primary, letterSpacing: 1,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '+91 ${_phoneController.text.trim()}',
                      style: GoogleFonts.inter(fontSize: 13, color: AppTheme.outline),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => setState(() { _otpSent = false; _otpController.clear(); }),
                child: Text('Edit', style: GoogleFonts.inter(fontSize: 13, color: AppTheme.primary)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),

        _fieldLabel('Enter OTP'),
        const SizedBox(height: 4),
        Text(
          'Sent to +91 ${_phoneController.text.trim()}',
          style: GoogleFonts.inter(fontSize: 13, color: AppTheme.outline),
        ),
        const SizedBox(height: 12),

        TextField(
          controller: _otpController,
          keyboardType: TextInputType.number,
          maxLength: 6,
          style: GoogleFonts.inter(
            fontSize: 28, letterSpacing: 10, fontWeight: FontWeight.w700,
            color: AppTheme.onSurface,
          ),
          decoration: InputDecoration(
            hintText: '••••••',
            hintStyle: GoogleFonts.inter(fontSize: 28, letterSpacing: 8, color: AppTheme.outlineVariant),
            prefixIcon: const Icon(Icons.lock_outline, size: 18),
            counterText: '',
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Sample OTP: 123456',
          style: GoogleFonts.inter(fontSize: 12, color: AppTheme.outline),
        ),
        const SizedBox(height: 12),

        if (isAdmin)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
              border: Border.all(color: AppTheme.outlineVariant),
            ),
            child: Row(
              children: [
                const Icon(Icons.admin_panel_settings, color: AppTheme.primary, size: 15),
                const SizedBox(width: 8),
                Text(
                  'Admin login — OTP is 123456',
                  style: GoogleFonts.inter(fontSize: 12, color: AppTheme.primary, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        const SizedBox(height: 24),

        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _verifyOtp,
            child: _isLoading
                ? const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.onPrimary),
                  )
                : Text(
                    'Verify & Continue',
                    style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _fieldLabel(String text) {
    return Text(
      text,
      style: GoogleFonts.inter(
        fontSize: 11, fontWeight: FontWeight.w600,
        color: AppTheme.onSurfaceVariant, letterSpacing: 0.8,
      ),
    );
  }
}

