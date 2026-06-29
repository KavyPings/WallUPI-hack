import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../providers/app_provider.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../services/native_sms_bridge.dart';
import '../widgets/ai_status_pill.dart';
import 'send_money_screen.dart';
import 'sms_analysis_screen.dart';
import 'profile_insights_screen.dart';
import 'transaction_history_screen.dart';
import 'login_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _navIndex = 0;

  final _pages = const [
    _HomeTab(),
    SmsAnalysisScreen(),
    ProfileInsightsScreen(),
    TransactionHistoryScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<AppProvider>().addListener(_onProviderChanged);
        _checkPendingIntent();
      }
    });
  }

  @override
  void dispose() {
    try {
      context.read<AppProvider>().removeListener(_onProviderChanged);
    } catch (_) {}
    super.dispose();
  }

  void _onProviderChanged() {
    if (mounted) {
      _checkPendingIntent();
    }
  }

  void _checkPendingIntent() {
    final provider = context.read<AppProvider>();
    final intent = provider.pendingPaymentIntent;
    if (intent != null) {
      provider.clearPendingPaymentIntent();
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SendMoneyScreen(paymentIntent: intent),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: _pages[_navIndex],
      bottomNavigationBar: _BottomNav(
        currentIndex: _navIndex,
        onTap: (i) => setState(() => _navIndex = i),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bottom nav
// ─────────────────────────────────────────────────────────────────────────────

class _BottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  const _BottomNav({required this.currentIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    const items = [
      (Icons.home_rounded, Icons.home_outlined, 'Home'),
      (Icons.sms_rounded, Icons.sms_outlined, 'SMS'),
      (Icons.person_rounded, Icons.person_outlined, 'Profile'),
      (Icons.history_rounded, Icons.history_outlined, 'History'),
    ];

    return Container(
      height: 68,
      decoration: const BoxDecoration(
        color: AppTheme.surfaceContainer,
        border: Border(top: BorderSide(color: AppTheme.outlineVariant, width: 1)),
      ),
      child: Row(
        children: List.generate(items.length, (i) {
          final (filledIcon, outlinedIcon, label) = items[i];
          final active = i == currentIndex;
          return Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onTap(i),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Active indicator dot
                  Container(
                    width: 4,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 4),
                    decoration: BoxDecoration(
                      color: active ? AppTheme.primary : Colors.transparent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  Icon(
                    active ? filledIcon : outlinedIcon,
                    color: active ? AppTheme.primary : AppTheme.outline,
                    size: 22,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    label,
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                      color: active ? AppTheme.primary : AppTheme.outline,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Home tab
// ─────────────────────────────────────────────────────────────────────────────

class _HomeTab extends StatelessWidget {
  const _HomeTab();

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, provider, _) {
        final user = provider.user;
        if (user == null) return const SizedBox();

        return SafeArea(
          bottom: false,
          child: CustomScrollView(
            slivers: [
              // ── Sticky header ──
              SliverPersistentHeader(
                pinned: true,
                delegate: _StickyHeader(user: user, provider: provider),
              ),

              // ── Balance hero card ──
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                  child: _HeroBalanceCard(user: user, provider: provider),
                ),
              ),

              // ── Risk banner ──
              if (provider.hasSuspiciousSms)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: _RiskBanner(provider: provider),
                  ),
                ),

              // ── Recent contacts ──
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 28, 0, 0),
                  child: _ContactsSection(provider: provider),
                ),
              ),

              // ── Offline UPI tip ──
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                  child: _OfflineUpiTip(),
                ),
              ),

              // ── Demo controls (admin) ──
              if (provider.isAdmin)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                    child: _DemoControls(provider: provider),
                  ),
                ),

              // ── Recent activity ──
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
                  child: _ActivitySection(provider: provider),
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 40)),
            ],
          ),
        );
      },
    );
  }
}

// ── Sticky app header ────────────────────────────────────────────────────────

class _StickyHeader extends SliverPersistentHeaderDelegate {
  final UserProfile user;
  final AppProvider provider;
  const _StickyHeader({required this.user, required this.provider});

  @override
  double get minExtent => 64;
  @override
  double get maxExtent => 64;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: AppTheme.surface,
      child: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  // Avatar
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppTheme.surfaceContainerHigh,
                      border: Border.all(color: AppTheme.outlineVariant),
                    ),
                    child: Center(
                      child: Text(
                        user.name[0].toUpperCase(),
                        style: GoogleFonts.inter(
                          fontSize: 14, fontWeight: FontWeight.w700,
                          color: AppTheme.onSurface,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'WALLUPI',
                            style: GoogleFonts.inter(
                              fontSize: 14, fontWeight: FontWeight.w700,
                              color: AppTheme.onSurface, letterSpacing: 2,
                            ),
                          ),
                          if (provider.isAdmin) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: AppTheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(3),
                                border: Border.all(color: AppTheme.outlineVariant),
                              ),
                              child: Text(
                                'ADMIN',
                                style: GoogleFonts.inter(
                                  fontSize: 8, fontWeight: FontWeight.w700,
                                  color: AppTheme.primary, letterSpacing: 1,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      Text(
                        user.upiId,
                        style: GoogleFonts.inter(
                          fontSize: 10, color: AppTheme.outline, letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),

                  // SMS notification
                  GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SmsAnalysisScreen()),
                    ),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: 36, height: 36,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppTheme.surfaceContainerLow,
                            border: Border.all(color: AppTheme.outlineVariant),
                          ),
                          child: Icon(
                            Icons.notifications_outlined,
                            size: 18,
                            color: provider.flaggedSms.isNotEmpty
                                ? AppTheme.danger
                                : AppTheme.outline,
                          ),
                        ),
                        if (provider.flaggedSms.isNotEmpty)
                          Positioned(
                            right: -2, top: -2,
                            child: Container(
                              width: 14, height: 14,
                              decoration: const BoxDecoration(
                                color: AppTheme.danger, shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Text(
                                  '${provider.flaggedSms.length}',
                                  style: const TextStyle(fontSize: 8, color: Colors.white, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),

                  // QR scanner
                  GestureDetector(
                    onTap: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => const SendMoneyScreen(triggeredByQr: true),
                    )),
                    child: Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppTheme.surfaceContainerLow,
                        border: Border.all(color: AppTheme.outlineVariant),
                      ),
                      child: const Icon(Icons.qr_code_scanner_rounded, size: 18, color: AppTheme.primary),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _LogoutMenu(provider: provider),
                ],
              ),
            ),
          ),
          const Divider(height: 1, color: AppTheme.outlineVariant),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(_StickyHeader oldDelegate) => false;
}

// ── Hero balance card ────────────────────────────────────────────────────────

class _HeroBalanceCard extends StatelessWidget {
  final UserProfile user;
  final AppProvider provider;
  const _HeroBalanceCard({required this.user, required this.provider});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppTheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.outlineVariant, width: 1),
        boxShadow: const [AppTheme.innerHighlight],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            // Ambient cobalt glow
            Positioned(
              top: -30,
              right: -30,
              child: Container(
                width: 160,
                height: 160,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [Color(0x1A638AFF), Colors.transparent],
                    radius: 0.9,
                  ),
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Balance label
                  Text(
                    'TOTAL BALANCE',
                    style: GoogleFonts.inter(
                      fontSize: 11, fontWeight: FontWeight.w600,
                      color: AppTheme.onSurfaceVariant, letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Balance amount
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        '₹',
                        style: GoogleFonts.inter(
                          fontSize: 20, fontWeight: FontWeight.w500,
                          color: AppTheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          NumberFormat('#,##,###').format(user.balance),
                          style: GoogleFonts.inter(
                            fontSize: 36, fontWeight: FontWeight.w600,
                            color: AppTheme.onSurface, letterSpacing: -1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'SBI Bank  ·  ${user.upiId}',
                    style: GoogleFonts.inter(
                      fontSize: 12, color: AppTheme.outline,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Action buttons row
                  Row(
                    children: [
                      // Add Money (ghost)
                      Expanded(
                        child: _CardButton(
                          label: 'Add Money',
                          icon: Icons.add_rounded,
                          isPrimary: false,
                          onTap: () => _showReceiveSheet(context, user),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Pay (cobalt)
                      Expanded(
                        child: _CardButton(
                          label: 'Pay',
                          icon: Icons.north_east_rounded,
                          isPrimary: true,
                          onTap: () => Navigator.push(context,
                            MaterialPageRoute(builder: (_) => const SendMoneyScreen())),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showReceiveSheet(BuildContext context, UserProfile user) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: AppTheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Text('Receive Money',
                style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w600, color: AppTheme.onSurface)),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppTheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.outlineVariant),
                boxShadow: const [AppTheme.innerHighlight],
              ),
              child: Column(
                children: [
                  Icon(Icons.qr_code_2, size: 100, color: AppTheme.onSurface),
                  const SizedBox(height: 16),
                  Text(user.upiId,
                      style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600, color: AppTheme.onSurface)),
                  const SizedBox(height: 4),
                  Text(user.name,
                      style: GoogleFonts.inter(fontSize: 13, color: AppTheme.outline)),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _CardButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isPrimary;
  final VoidCallback onTap;

  const _CardButton({
    required this.label,
    required this.icon,
    required this.isPrimary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: isPrimary ? AppTheme.accent : AppTheme.surfaceContainer,
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          border: Border.all(
            color: isPrimary ? Colors.transparent : AppTheme.outlineVariant,
          ),
          boxShadow: isPrimary ? const [AppTheme.cobaltGlow] : [],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: isPrimary ? Colors.white : AppTheme.onSurface),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 13, fontWeight: FontWeight.w600,
                color: isPrimary ? Colors.white : AppTheme.onSurface,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Risk banner ──────────────────────────────────────────────────────────────

class _RiskBanner extends StatelessWidget {
  final AppProvider provider;
  const _RiskBanner({required this.provider});

  @override
  Widget build(BuildContext context) {
    final sms = provider.activeSuspiciousSms!;
    return GestureDetector(
      onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => const SmsAnalysisScreen())),
      child: Container(
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
              Container(width: 3, color: AppTheme.danger),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: AppTheme.danger, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Suspicious SMS Detected',
                              style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.onSurface)),
                            Text('From: ${sms.sender}  ·  Risk: ${(sms.localRiskScore * 100).round()}%',
                              style: GoogleFonts.inter(fontSize: 11, color: AppTheme.outline)),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: AppTheme.outline, size: 18),
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
}

// ── Recent contacts horizontal scroll ────────────────────────────────────────

class _ContactsSection extends StatelessWidget {
  final AppProvider provider;
  const _ContactsSection({required this.provider});

  @override
  Widget build(BuildContext context) {
    // Get top contacts from recent transactions
    final contactMap = <String, _Contact>{};
    for (final t in provider.transactions) {
      if (!t.isIncoming) {
        contactMap[t.recipientName] ??= _Contact(t.recipientName, t.recipientUpiId);
      }
    }
    final contacts = contactMap.values.take(8).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Row(
            children: [
              Text(
                'RECENT CONTACTS',
                style: GoogleFonts.inter(
                  fontSize: 11, fontWeight: FontWeight.w600,
                  color: AppTheme.outline, letterSpacing: 1.5,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => const SendMoneyScreen())),
                child: Text(
                  'Send New',
                  style: GoogleFonts.inter(
                    fontSize: 11, fontWeight: FontWeight.w600,
                    color: AppTheme.primary, letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 88,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            children: [
              // "New" add button
              _ContactAvatar(
                initials: '+',
                label: 'New',
                onTap: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => const SendMoneyScreen())),
                isDashed: true,
              ),
              const SizedBox(width: 20),
              ...contacts.map((c) => Padding(
                padding: const EdgeInsets.only(right: 20),
                child: _ContactAvatar(
                  initials: c.name[0].toUpperCase(),
                  label: c.name.split(' ').first,
                  onTap: () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => SendMoneyScreen(prefilledUpiId: c.upiId))),
                ),
              )),
            ],
          ),
        ),
      ],
    );
  }
}

class _Contact {
  final String name;
  final String upiId;
  _Contact(this.name, this.upiId);
}

class _ContactAvatar extends StatelessWidget {
  final String initials;
  final String label;
  final VoidCallback onTap;
  final bool isDashed;

  const _ContactAvatar({
    required this.initials,
    required this.label,
    required this.onTap,
    this.isDashed = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isDashed ? Colors.transparent : AppTheme.surfaceContainerHigh,
              border: Border.all(
                color: AppTheme.outlineVariant,
                strokeAlign: BorderSide.strokeAlignCenter,
                style: isDashed ? BorderStyle.none : BorderStyle.solid,
              ),
            ),
            child: isDashed
                ? CustomPaint(
                    painter: _DashedCirclePainter(color: AppTheme.outlineVariant),
                    child: Center(
                      child: Icon(Icons.add, size: 22, color: AppTheme.outline),
                    ),
                  )
                : Center(
                    child: Text(
                      initials,
                      style: GoogleFonts.inter(
                        fontSize: 18, fontWeight: FontWeight.w600,
                        color: AppTheme.onSurface,
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11, fontWeight: FontWeight.w500,
              color: isDashed ? AppTheme.outline : AppTheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _DashedCirclePainter extends CustomPainter {
  final Color color;
  const _DashedCirclePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 1;
    const dashCount = 16;
    const dashLength = 0.18;
    const gapLength = 0.07;

    for (int i = 0; i < dashCount; i++) {
      final startAngle = i * (dashLength + gapLength) * 2 * 3.14159 / dashCount;
      final sweepAngle = dashLength * 2 * 3.14159 / dashCount;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DashedCirclePainter oldDelegate) => false;
}

// ── Offline UPI tip ──────────────────────────────────────────────────────────

class _OfflineUpiTip extends StatelessWidget {
  const _OfflineUpiTip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1F2D),
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: const Color(0xFF1E4060), width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: const Color(0xFF0A3050),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.wifi_off_rounded, size: 16, color: Color(0xFF4FC3F7)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Try this: Offline UPI Payments',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF4FC3F7),
                    letterSpacing: 0.1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Turn off WiFi & mobile data, then try to pay — Wallupi switches to offline UPI automatically.',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: AppTheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Demo controls (admin) ─────────────────────────────────────────────────────

class _DemoControls extends StatefulWidget {
  final AppProvider provider;
  const _DemoControls({required this.provider});

  @override
  State<_DemoControls> createState() => _DemoControlsState();
}

class _DemoControlsState extends State<_DemoControls> {
  bool? _cloudOn;
  bool? _tinyBertOn;

  @override
  void initState() {
    super.initState();
    _checkAiStatus();
  }

  Future<void> _checkAiStatus() async {
    if (!mounted) return;
    setState(() { _cloudOn = null; _tinyBertOn = null; });

    // Cloud AI — probe backend /status
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

    // TinyBERT — query native Android bridge
    try {
      final status = await NativeSmsBridge.getDetectorStatus();
      if (mounted) setState(() => _tinyBertOn = status?.modelAvailable ?? false);
    } catch (_) {
      if (mounted) setState(() => _tinyBertOn = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = widget.provider;
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: AppTheme.outlineVariant),
        boxShadow: const [AppTheme.innerHighlight],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.science_outlined, size: 13, color: AppTheme.outline),
              const SizedBox(width: 6),
              Text(
                'DEMO CONTROLS',
                style: GoogleFonts.inter(
                  fontSize: 10, fontWeight: FontWeight.w700,
                  color: AppTheme.outline, letterSpacing: 1.5,
                ),
              ),
              const Spacer(),
              // AI status pills
              AiStatusPill(label: 'Cloud AI', isOn: _cloudOn),
              const SizedBox(width: 6),
              AiStatusPill(label: 'TinyBERT', isOn: _tinyBertOn),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: _checkAiStatus,
                child: const Icon(Icons.refresh_rounded, size: 14, color: AppTheme.outline),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (provider.hasRealCall)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                border: Border.all(color: AppTheme.outlineVariant),
              ),
              child: Row(
                children: [
                  const Icon(Icons.call_rounded, size: 13, color: AppTheme.danger),
                  const SizedBox(width: 6),
                  Text('Real call active',
                      style: GoogleFonts.inter(fontSize: 11, color: AppTheme.danger, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
          _switch('Simulate Active Call', 'Boosts risk during payments',
              provider.isOnCall, provider.hasRealCall ? null : provider.toggleCallState),
          _switch('Unknown Caller', 'Further raises risk',
              provider.isUnknownCaller,
              (provider.isOnCall && !provider.hasRealCall) ? provider.toggleUnknownCaller : null),
          Container(height: 1, color: AppTheme.outlineVariant, margin: const EdgeInsets.symmetric(vertical: 10)),
          _switch('Registered UPI Business', 'NPCI-verified — halves all risk',
              provider.isRegisteredUpiId, provider.toggleRegisteredUpiId),
        ],
      ),
    );
  }

  Widget _switch(String title, String sub, bool value, void Function(bool)? fn) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: GoogleFonts.inter(
                  fontSize: 13, fontWeight: FontWeight.w500,
                  color: fn == null ? AppTheme.outlineVariant : AppTheme.onSurface)),
                Text(sub, style: GoogleFonts.inter(fontSize: 11, color: AppTheme.outline)),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: fn,
            activeTrackColor: AppTheme.accent,
            activeThumbColor: Colors.white,
            inactiveThumbColor: AppTheme.outline,
            inactiveTrackColor: AppTheme.surfaceContainerHighest,
            trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
          ),
        ],
      ),
    );
  }
}

// ── Recent activity ───────────────────────────────────────────────────────────

class _ActivitySection extends StatelessWidget {
  final AppProvider provider;
  const _ActivitySection({required this.provider});

  @override
  Widget build(BuildContext context) {
    final transactions = provider.transactions.take(6).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'RECENT ACTIVITY',
              style: GoogleFonts.inter(
                fontSize: 11, fontWeight: FontWeight.w600,
                color: AppTheme.outline, letterSpacing: 1.5,
              ),
            ),
            const Spacer(),
            GestureDetector(
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const TransactionHistoryScreen())),
              child: Text(
                'See All',
                style: GoogleFonts.inter(
                  fontSize: 11, fontWeight: FontWeight.w600,
                  color: AppTheme.primary, letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        if (transactions.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  Icon(Icons.receipt_long_outlined, size: 36, color: AppTheme.outlineVariant),
                  const SizedBox(height: 12),
                  Text('No transactions yet',
                      style: GoogleFonts.inter(fontSize: 14, color: AppTheme.outline)),
                ],
              ),
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              color: AppTheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
              border: Border.all(color: AppTheme.outlineVariant),
              boxShadow: const [AppTheme.innerHighlight],
            ),
            child: Column(
              children: List.generate(transactions.length, (i) {
                final txn = transactions[i];
                final isLast = i == transactions.length - 1;
                return Column(
                  children: [
                    _TxnRow(txn: txn),
                    if (!isLast)
                      Container(
                        height: 1,
                        margin: const EdgeInsets.only(left: 72),
                        color: AppTheme.outlineVariant,
                      ),
                  ],
                );
              }),
            ),
          ),
      ],
    );
  }
}

// ── Transaction row ───────────────────────────────────────────────────────────

class _TxnRow extends StatelessWidget {
  final Transaction txn;
  const _TxnRow({required this.txn});

  @override
  Widget build(BuildContext context) {
    final isIncoming = txn.isIncoming;
    final isCancelled = txn.status == 'cancelled';

    return SizedBox(
      height: 64,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.surfaceContainerHighest,
                border: Border.all(color: AppTheme.outlineVariant),
              ),
              child: Icon(
                isCancelled
                    ? Icons.close_rounded
                    : isIncoming ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                size: 17,
                color: isCancelled
                    ? AppTheme.danger
                    : isIncoming ? AppTheme.primaryContainer : AppTheme.outline,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    txn.recipientName,
                    style: GoogleFonts.inter(
                      fontSize: 14, fontWeight: FontWeight.w500,
                      color: AppTheme.onSurface,
                    ),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    DateFormat('d MMM · h:mm a').format(txn.timestamp),
                    style: GoogleFonts.inter(fontSize: 11, color: AppTheme.outline),
                  ),
                ],
              ),
            ),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${isIncoming ? '+' : '−'} ₹${txn.amount.toStringAsFixed(0)}',
                  style: GoogleFonts.inter(
                    fontSize: 14, fontWeight: FontWeight.w600,
                    color: isCancelled
                        ? AppTheme.outlineVariant
                        : isIncoming ? AppTheme.primaryContainer : AppTheme.onSurface,
                    decoration: isCancelled ? TextDecoration.lineThrough : null,
                  ),
                ),
                if (txn.riskScore > 20) ...[
                  const SizedBox(height: 2),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: AppTheme.outlineVariant),
                    ),
                    child: Text(
                      AppTheme.getRiskLabel(txn.riskScore),
                      style: GoogleFonts.inter(
                        fontSize: 9, fontWeight: FontWeight.w600,
                        color: AppTheme.getRiskColor(txn.riskScore), letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Logout menu
// ─────────────────────────────────────────────────────────────────────────────

class _LogoutMenu extends StatelessWidget {
  final AppProvider provider;
  const _LogoutMenu({required this.provider});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      color: AppTheme.surfaceContainerHigh,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        side: const BorderSide(color: AppTheme.outlineVariant),
      ),
      icon: const Icon(Icons.more_vert, size: 20, color: AppTheme.outline),
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'logout',
          child: Row(
            children: [
              const Icon(Icons.logout, size: 16, color: AppTheme.danger),
              const SizedBox(width: 8),
              Text('Logout', style: GoogleFonts.inter(color: AppTheme.danger, fontWeight: FontWeight.w500, fontSize: 14)),
            ],
          ),
        ),
      ],
      onSelected: (value) async {
        if (value != 'logout') return;
        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('Logout', style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: AppTheme.onSurface)),
            content: Text('Are you sure you want to logout?',
                style: GoogleFonts.inter(color: AppTheme.onSurfaceVariant, fontSize: 14)),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel')),
              TextButton(onPressed: () => Navigator.pop(ctx, true),
                  child: Text('Logout', style: GoogleFonts.inter(color: AppTheme.danger, fontWeight: FontWeight.w600))),
            ],
          ),
        );
        if (confirm == true && context.mounted) {
          await provider.logout();
          if (context.mounted) {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const LoginScreen()),
              (route) => false,
            );
          }
        }
      },
    );
  }
}
