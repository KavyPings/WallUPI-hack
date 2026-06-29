import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../providers/app_provider.dart';
import 'login_screen.dart';

class ProfileInsightsScreen extends StatelessWidget {
  const ProfileInsightsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, provider, _) {
        final user = provider.user;
        if (user == null) return const SizedBox();

        final transactions = provider.transactions;
        final totalSent = transactions
            .where((t) => !t.isIncoming && t.status == 'success')
            .fold(0.0, (sum, t) => sum + t.amount);
        final totalReceived = transactions
            .where((t) => t.isIncoming && t.status == 'success')
            .fold(0.0, (sum, t) => sum + t.amount);
        final riskyCount = transactions.where((t) => t.riskScore >= 50).length;
        final safeCount = transactions.where((t) => t.riskScore < 50).length;

        final contactMap = <String, int>{};
        for (final t in transactions) {
          contactMap[t.recipientName] = (contactMap[t.recipientName] ?? 0) + 1;
        }
        final topContacts = contactMap.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

        return Scaffold(
          backgroundColor: AppTheme.background,
          body: CustomScrollView(
            slivers: [
              // ── Editorial header (no AppBar) ──
              SliverToBoxAdapter(
                child: Container(
                  color: AppTheme.surface,
                  child: Column(
                    children: [
                      const SizedBox(height: 56), // status bar clearance
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                        child: Column(
                          children: [
                            // Avatar circle
                            Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppTheme.surfaceContainerHigh,
                                border: Border.all(color: AppTheme.outlineVariant, width: 1.5),
                                boxShadow: const [AppTheme.innerHighlight],
                              ),
                              child: Center(
                                child: Text(
                                  user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                                  style: GoogleFonts.inter(fontSize: 34, fontWeight: FontWeight.w600, color: AppTheme.onSurface),
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),

                            // Name (display-lg size)
                            Text(
                              user.name,
                              style: GoogleFonts.inter(fontSize: 28, fontWeight: FontWeight.w700, color: AppTheme.onSurface, letterSpacing: -0.8),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '+91 ${user.phone}',
                              style: GoogleFonts.inter(fontSize: 14, color: AppTheme.outline, letterSpacing: 0.3),
                            ),
                            const SizedBox(height: 10),

                            // Status chip
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                              decoration: BoxDecoration(
                                color: AppTheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(100),
                                border: Border.all(color: AppTheme.outlineVariant),
                              ),
                              child: Text(
                                provider.isAdmin ? '⚡  Admin' : '✓  Verified',
                                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.primary),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1, color: AppTheme.outlineVariant),
                    ],
                  ),
                ),
              ),

              // ── Content ──
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([

                    // ACCOUNT section
                    _SectionLabel('ACCOUNT'),
                    const SizedBox(height: 8),
                    _InfoCard(children: [
                      _StatRow('Balance', '₹${user.balance.toStringAsFixed(2)}'),
                      const _Divider(),
                      _StatRow('Total Sent', '₹${totalSent.toStringAsFixed(0)}'),
                      const _Divider(),
                      _StatRow('Total Received', '₹${totalReceived.toStringAsFixed(0)}'),
                      const _Divider(),
                      _StatRow('Avg Transaction', '₹${user.avgTransactionAmount.toStringAsFixed(0)}'),
                      const _Divider(),
                      _StatRow('Typical Hour', '${user.typicalTransactionHour}:00'),
                    ]),
                    const SizedBox(height: 20),

                    // SECURITY section
                    _SectionLabel('SECURITY'),
                    const SizedBox(height: 8),
                    _InfoCard(children: [
                      _StatRow('SMS Scanned', '${provider.smsMessages.length}'),
                      const _Divider(),
                      _StatRow('Flagged SMS', '${provider.flaggedSms.length}',
                          valueColor: provider.flaggedSms.isNotEmpty ? AppTheme.danger : null),
                      const _Divider(),
                      _StatRow('Safe Transactions', '$safeCount', valueColor: AppTheme.riskSafe),
                      const _Divider(),
                      _StatRow('Risky Transactions', '$riskyCount',
                          valueColor: riskyCount > 0 ? AppTheme.danger : null),
                    ]),
                    const SizedBox(height: 20),

                    // FREQUENT CONTACTS
                    if (topContacts.isNotEmpty) ...[
                      _SectionLabel('FREQUENT CONTACTS'),
                      const SizedBox(height: 8),
                      _InfoCard(children: List.generate(
                        topContacts.take(5).length,
                        (i) {
                          final entry = topContacts[i];
                          final isLast = i == topContacts.take(5).length - 1;
                          return Column(children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              child: Row(children: [
                                Container(
                                  width: 36, height: 36,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: AppTheme.surfaceContainerHighest,
                                    border: Border.all(color: AppTheme.outlineVariant),
                                  ),
                                  child: Center(child: Text(
                                    entry.key.isNotEmpty ? entry.key[0].toUpperCase() : '?',
                                    style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.onSurface),
                                  )),
                                ),
                                const SizedBox(width: 12),
                                Expanded(child: Text(entry.key, style: GoogleFonts.inter(fontSize: 14, color: AppTheme.onSurface))),
                                Text('${entry.value} txns', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.outline)),
                              ]),
                            ),
                            if (!isLast) const _Divider(),
                          ]);
                        },
                      )),
                      const SizedBox(height: 20),
                    ],

                    // ADMIN section
                    if (provider.isAdmin) ...[
                      _SectionLabel('ADMIN'),
                      const SizedBox(height: 8),
                      _InfoCard(children: [
                        _SettingRow(Icons.bug_report_outlined, 'Demo Mode Active'),
                        const _Divider(),
                        _SettingRow(Icons.attach_money_rounded, 'Unlimited Balance'),
                        const _Divider(),
                        _SettingRow(Icons.message_outlined, 'Demo SMS Loaded'),
                      ]),
                      const SizedBox(height: 20),
                    ],

                    // PREFERENCES section
                    _SectionLabel('PREFERENCES'),
                    const SizedBox(height: 8),
                    _InfoCard(children: [
                      _SettingRow(Icons.notifications_outlined, 'Notifications',
                          trailing: const Icon(Icons.chevron_right, size: 18, color: AppTheme.onSurfaceVariant)),
                      const _Divider(),
                      _SettingRow(Icons.security_outlined, 'Privacy & Security',
                          trailing: const Icon(Icons.chevron_right, size: 18, color: AppTheme.onSurfaceVariant)),
                      const _Divider(),
                      _SettingRow(Icons.help_outline, 'Help & Support',
                          trailing: const Icon(Icons.chevron_right, size: 18, color: AppTheme.onSurfaceVariant)),
                    ]),
                    const SizedBox(height: 24),

                    // Logout button
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.logout_rounded, size: 18, color: AppTheme.danger),
                        label: Text('Log Out', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w500, color: AppTheme.danger)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppTheme.outlineVariant),
                          foregroundColor: AppTheme.danger,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusSmall)),
                        ),
                        onPressed: () => _confirmLogout(context, provider),
                      ),
                    ),
                  ]),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _confirmLogout(BuildContext context, AppProvider provider) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceContainer,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          side: const BorderSide(color: AppTheme.outlineVariant),
        ),
        title: Text('Log Out', style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w600, color: AppTheme.onSurface)),
        content: Text('Are you sure you want to log out?', style: GoogleFonts.inter(fontSize: 14, color: AppTheme.onSurfaceVariant)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.inter(color: AppTheme.onSurfaceVariant)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.danger, foregroundColor: Colors.white, elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusSmall)),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              await provider.logout();
              if (context.mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (route) => false,
                );
              }
            },
            child: Text('Log Out', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

// ── Shared sub-widgets ──

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.onSurfaceVariant, letterSpacing: 1.2),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final List<Widget> children;
  const _InfoCard({required this.children});
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: AppTheme.outlineVariant),
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(children: children),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) => const Divider(height: 1, thickness: 1, color: AppTheme.outlineVariant);
}

class _StatRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  const _StatRow(this.label, this.value, {this.valueColor});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.inter(fontSize: 14, color: AppTheme.onSurfaceVariant)),
          Text(value, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: valueColor ?? AppTheme.onSurface)),
        ],
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget? trailing;
  const _SettingRow(this.icon, this.label, {this.trailing});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(children: [
        Icon(icon, size: 18, color: AppTheme.onSurfaceVariant),
        const SizedBox(width: 12),
        Expanded(child: Text(label, style: GoogleFonts.inter(fontSize: 14, color: AppTheme.onSurface))),
        if (trailing != null) trailing!,
      ]),
    );
  }
}
