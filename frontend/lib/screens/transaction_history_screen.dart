import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../providers/app_provider.dart';
import '../models/models.dart';

// ─────────────────────────────────────────────────────────────
// Flag dialog (exported to payment_success_screen)
// ─────────────────────────────────────────────────────────────
Future<void> showFlagDialog(
  BuildContext context, {
  String? flaggedUpiId,
  String? flaggedPhone,
  String displayName = '',
}) async {
  String selectedReason = 'spam';
  final noteController = TextEditingController();

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) => AlertDialog(
        backgroundColor: AppTheme.surfaceContainer,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          side: const BorderSide(color: AppTheme.outlineVariant),
        ),
        title: Text(
          'Report ${displayName.isNotEmpty ? displayName : (flaggedUpiId ?? flaggedPhone ?? '')}',
          style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 16, color: AppTheme.onSurface),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Reason', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6, runSpacing: 6,
              children: ['spam', 'fraud', 'scam', 'harassment'].map((r) {
                final selected = selectedReason == r;
                return GestureDetector(
                  onTap: () => setDialogState(() => selectedReason = r),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: selected ? AppTheme.surfaceContainerHighest : AppTheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                      border: Border.all(color: selected ? AppTheme.danger : AppTheme.outlineVariant),
                    ),
                    child: Text(
                      r[0].toUpperCase() + r.substring(1),
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                        color: selected ? AppTheme.danger : AppTheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: noteController,
              style: GoogleFonts.inter(fontSize: 13, color: AppTheme.onSurface),
              decoration: InputDecoration(
                hintText: 'Add a note (optional)',
                hintStyle: GoogleFonts.inter(fontSize: 13, color: AppTheme.textLight),
                filled: true,
                fillColor: AppTheme.surfaceContainerHigh,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                  borderSide: const BorderSide(color: AppTheme.outlineVariant),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                  borderSide: const BorderSide(color: AppTheme.outlineVariant),
                ),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.inter(color: AppTheme.onSurfaceVariant)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.danger, foregroundColor: Colors.white, elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusSmall)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Report', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    ),
  );

  if (confirmed != true || !context.mounted) return;

  final provider = Provider.of<AppProvider>(context, listen: false);
  final success = await provider.flagAsSpam(
    flaggedUpiId: flaggedUpiId, flaggedPhone: flaggedPhone,
    reason: selectedReason,
    note: noteController.text.trim().isEmpty ? null : noteController.text.trim(),
  );

  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(success ? 'Reported successfully.' : 'Could not report — please try again.'),
    backgroundColor: success ? AppTheme.secondary : AppTheme.danger,
  ));
  noteController.dispose();
}

// ─────────────────────────────────────────────────────────────
// Main Screen
// ─────────────────────────────────────────────────────────────
class TransactionHistoryScreen extends StatefulWidget {
  const TransactionHistoryScreen({super.key});

  @override
  State<TransactionHistoryScreen> createState() => _TransactionHistoryScreenState();
}

class _TransactionHistoryScreenState extends State<TransactionHistoryScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  String _activeFilter = 'All';
  final List<String> _filters = ['All', 'Sent', 'Received', 'Blocked'];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Transaction> _applyFilters(List<Transaction> all) {
    return all.where((t) {
      // Search filter
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        if (!t.recipientName.toLowerCase().contains(q) &&
            !t.recipientUpiId.toLowerCase().contains(q) &&
            !t.amount.toString().contains(q)) {
          return false;
        }
      }
      // Category filter
      switch (_activeFilter) {
        case 'Sent':     return !t.isIncoming && t.status != 'cancelled';
        case 'Received': return t.isIncoming;
        case 'Blocked':  return t.status == 'cancelled';
        default:         return true;
      }
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, provider, _) {
        final filtered = _applyFilters(provider.transactions);

        return Scaffold(
          backgroundColor: AppTheme.background,
          body: Column(
            children: [
              // ── Custom sticky header ──
              Container(
                color: AppTheme.surface,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top bar
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 56, 20, 0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Transactions',
                            style: GoogleFonts.inter(fontSize: 28, fontWeight: FontWeight.w700, color: AppTheme.onSurface, letterSpacing: -0.8),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppTheme.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                              border: Border.all(color: AppTheme.outlineVariant),
                            ),
                            child: Text(
                              '${filtered.length} total',
                              style: GoogleFonts.inter(fontSize: 12, color: AppTheme.onSurfaceVariant, fontWeight: FontWeight.w500),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Text(
                        'Track and manage your payments.',
                        style: GoogleFonts.inter(fontSize: 13, color: AppTheme.outline),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Search bar
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: TextField(
                        controller: _searchController,
                        style: GoogleFonts.inter(fontSize: 14, color: AppTheme.onSurface),
                        onChanged: (v) => setState(() => _searchQuery = v),
                        decoration: InputDecoration(
                          hintText: 'Search recipients, amounts...',
                          hintStyle: GoogleFonts.inter(fontSize: 14, color: AppTheme.outline),
                          prefixIcon: const Icon(Icons.search, size: 20),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 18),
                                  onPressed: () => setState(() { _searchController.clear(); _searchQuery = ''; }),
                                )
                              : null,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Filter chips
                    SizedBox(
                      height: 36,
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        scrollDirection: Axis.horizontal,
                        itemCount: _filters.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (_, i) {
                          final f = _filters[i];
                          final active = f == _activeFilter;
                          return GestureDetector(
                            onTap: () => setState(() => _activeFilter = f),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: active ? AppTheme.surfaceContainerHigh : Colors.transparent,
                                borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                                border: Border.all(
                                  color: active ? AppTheme.primary : AppTheme.outlineVariant,
                                ),
                              ),
                              child: Text(
                                f,
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                                  color: active ? AppTheme.primary : AppTheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Divider(height: 1, color: AppTheme.outlineVariant),
                  ],
                ),
              ),

              // ── List ──
              Expanded(
                child: filtered.isEmpty
                    ? _buildEmpty()
                    : _buildList(context, filtered),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.receipt_long_outlined, size: 48, color: AppTheme.textLight),
          const SizedBox(height: 12),
          Text(
            _searchQuery.isNotEmpty ? 'No results for "$_searchQuery"' : 'No transactions yet',
            style: GoogleFonts.inter(fontSize: 15, color: AppTheme.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          Text(
            _searchQuery.isNotEmpty ? 'Try a different search term' : 'Your payment history will appear here',
            style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textLight),
          ),
        ],
      ),
    );
  }

  Widget _buildList(BuildContext context, List<Transaction> transactions) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    final todayTxns = transactions.where((t) => t.timestamp.isAfter(today)).toList();
    final yesterdayTxns = transactions.where((t) => t.timestamp.isAfter(yesterday) && t.timestamp.isBefore(today)).toList();
    final earlierTxns = transactions.where((t) => t.timestamp.isBefore(yesterday)).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        if (todayTxns.isNotEmpty) ...[
          _GroupHeader('Today'),
          _TxnGroup(transactions: todayTxns),
          const SizedBox(height: 20),
        ],
        if (yesterdayTxns.isNotEmpty) ...[
          _GroupHeader('Yesterday'),
          _TxnGroup(transactions: yesterdayTxns),
          const SizedBox(height: 20),
        ],
        if (earlierTxns.isNotEmpty) ...[
          _GroupHeader('Earlier'),
          _TxnGroup(transactions: earlierTxns),
        ],
      ],
    );
  }
}

class _GroupHeader extends StatelessWidget {
  final String label;
  const _GroupHeader(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 2),
      child: Text(
        label.toUpperCase(),
        style: GoogleFonts.inter(
          fontSize: 11, fontWeight: FontWeight.w600,
          color: AppTheme.onSurfaceVariant, letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _TxnGroup extends StatelessWidget {
  final List<Transaction> transactions;
  const _TxnGroup({required this.transactions});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: AppTheme.outlineVariant),
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(
        children: List.generate(transactions.length, (i) {
          final txn = transactions[i];
          final isLast = i == transactions.length - 1;
          return Column(
            children: [
              _TxnRow(transaction: txn),
              if (!isLast)
                const Divider(height: 1, thickness: 1, indent: 72, color: AppTheme.outlineVariant),
            ],
          );
        }),
      ),
    );
  }
}

class _TxnRow extends StatelessWidget {
  final Transaction transaction;
  const _TxnRow({required this.transaction});

  @override
  Widget build(BuildContext context) {
    final txn = transaction;
    final riskColor = AppTheme.getRiskColor(txn.riskScore);
    final isIncoming = txn.isIncoming;
    final isCancelled = txn.status == 'cancelled';

    final iconColor = isCancelled ? AppTheme.danger : isIncoming ? AppTheme.primary : AppTheme.onSurfaceVariant;
    final iconData = isCancelled ? Icons.cancel_outlined : isIncoming ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded;

    return InkWell(
      onTap: () => _showDetail(context, txn),
      child: SizedBox(
        height: 64,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              // Leading circle
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isIncoming ? AppTheme.surfaceContainerHighest : AppTheme.surfaceContainerHighest,
                  border: Border.all(color: AppTheme.outlineVariant),
                ),
                child: Icon(iconData, color: iconColor, size: 18),
              ),
              const SizedBox(width: 12),

              // Name + time
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      txn.recipientName,
                      style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500, color: AppTheme.onSurface),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      DateFormat('hh:mm a').format(txn.timestamp),
                      style: GoogleFonts.inter(fontSize: 12, color: AppTheme.outline, letterSpacing: 0.1),
                    ),
                  ],
                ),
              ),

              // Amount + risk chip
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${isIncoming ? '+' : '−'} ₹${txn.amount.toStringAsFixed(0)}',
                    style: GoogleFonts.inter(
                      fontSize: 14, fontWeight: FontWeight.w600,
                      color: isCancelled ? AppTheme.textLight : isIncoming ? AppTheme.primary : AppTheme.onSurface,
                      decoration: isCancelled ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  if (txn.riskScore > 20 || isCancelled) ...[
                    const SizedBox(height: 2),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                        border: Border.all(color: isCancelled ? AppTheme.danger : riskColor),
                      ),
                      child: Text(
                        isCancelled ? 'Blocked' : AppTheme.getRiskLabel(txn.riskScore),
                        style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: isCancelled ? AppTheme.danger : riskColor),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDetail(BuildContext context, Transaction txn) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
        side: BorderSide(color: AppTheme.outlineVariant),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(color: AppTheme.outlineVariant, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            Text('Transaction Details', style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w600, color: AppTheme.onSurface)),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                color: AppTheme.surfaceContainer,
                borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                border: Border.all(color: AppTheme.outlineVariant),
              ),
              child: Column(children: [
                _sheetRow('Recipient', txn.recipientName),
                const Divider(height: 1, color: AppTheme.outlineVariant),
                _sheetRow('UPI ID', txn.recipientUpiId),
                const Divider(height: 1, color: AppTheme.outlineVariant),
                _sheetRow('Amount', '₹${txn.amount.toStringAsFixed(2)}'),
                const Divider(height: 1, color: AppTheme.outlineVariant),
                _sheetRow('Date', DateFormat('dd MMM yyyy, hh:mm a').format(txn.timestamp)),
                const Divider(height: 1, color: AppTheme.outlineVariant),
                _sheetRow('Status', txn.status.toUpperCase()),
                if (txn.note.isNotEmpty) ...[
                  const Divider(height: 1, color: AppTheme.outlineVariant),
                  _sheetRow('Note', txn.note),
                ],
                const Divider(height: 1, color: AppTheme.outlineVariant),
                _sheetRow('Risk', '${txn.riskScore}% — ${AppTheme.getRiskLabel(txn.riskScore)}', valueColor: AppTheme.getRiskColor(txn.riskScore)),
              ]),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity, height: 44,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.flag_outlined, size: 15, color: AppTheme.danger),
                label: Text('Report as Spam', style: GoogleFonts.inter(fontSize: 13, color: AppTheme.danger)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppTheme.outlineVariant),
                  foregroundColor: AppTheme.danger,
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  showFlagDialog(context, flaggedUpiId: txn.recipientUpiId, displayName: txn.recipientName);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sheetRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 90,
          child: Text(label, style: GoogleFonts.inter(fontSize: 13, color: AppTheme.onSurfaceVariant)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(value, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: valueColor ?? AppTheme.onSurface)),
        ),
      ]),
    );
  }
}
