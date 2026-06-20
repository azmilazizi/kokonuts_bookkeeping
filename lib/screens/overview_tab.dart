import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'dart:math' as math;

import '../app/app_state.dart';
import '../models/overview_transaction.dart';
import '../services/bills_service.dart';
import '../services/expenses_service.dart';
import '../services/overview_service.dart';
import '../services/purchase_orders_service.dart';
import '../services/purchase_order_detail_service.dart';

const _kPOColor = Color(0xFF6366F1);
const _kExpenseColor = Color(0xFF10B981);
const _kBillColor = Color(0xFFF59E0B);

const _kChartColors = [
  Color(0xFF6366F1),
  Color(0xFF10B981),
  Color(0xFFF59E0B),
  Color(0xFFEF4444),
  Color(0xFF8B5CF6),
  Color(0xFF06B6D4),
  Color(0xFFEC4899),
  Color(0xFFF97316),
  Color(0xFF14B8A6),
  Color(0xFF84CC16),
];

enum _QuickPeriod { thisMonth, lastMonth, thisQuarter, thisYear, custom }

class OverviewTab extends StatefulWidget {
  const OverviewTab({super.key, required this.appState});

  final AppState appState;

  @override
  State<OverviewTab> createState() => _OverviewTabState();
}

class _OverviewTabState extends State<OverviewTab>
    with AutomaticKeepAliveClientMixin {
  late final OverviewService _service;
  late final ExpensesService _expensesService;
  late final BillsService _billsService;
  late final PurchaseOrdersService _purchaseOrdersService;
  late final PurchaseOrderDetailService _purchaseOrderDetailService;

  late DateTime _startDate;
  late DateTime _endDate;
  _QuickPeriod _quickPeriod = _QuickPeriod.thisMonth;

  bool _isLoading = false;
  bool _isChartLoading = false;
  bool _isTransactionsLoading = false;
  String? _errorMessage;
  String? _transactionsError;
  MoneyOutSummary? _summary;
  ExpensesPieChartData? _expensesPercentage;
  String _accountingMethod = 'payment';
  List<OverviewTransaction> _transactions = [];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _applyQuickPeriod(_QuickPeriod.thisMonth, fetch: false);
    _service = OverviewService();
    _expensesService = ExpensesService();
    _billsService = BillsService();
    _purchaseOrdersService = PurchaseOrdersService();
    _purchaseOrderDetailService = PurchaseOrderDetailService();
    _fetchAll();
  }

  void _applyQuickPeriod(_QuickPeriod period, {bool fetch = true}) {
    final now = DateTime.now();
    DateTime start;
    DateTime end;

    switch (period) {
      case _QuickPeriod.thisMonth:
        start = DateTime(now.year, now.month, 1);
        end = DateTime(now.year, now.month + 1, 0);
        break;
      case _QuickPeriod.lastMonth:
        start = DateTime(now.year, now.month - 1, 1);
        end = DateTime(now.year, now.month, 0);
        break;
      case _QuickPeriod.thisQuarter:
        final q = (now.month - 1) ~/ 3;
        start = DateTime(now.year, q * 3 + 1, 1);
        end = DateTime(now.year, q * 3 + 4, 0);
        break;
      case _QuickPeriod.thisYear:
        start = DateTime(now.year, 1, 1);
        end = DateTime(now.year, 12, 31);
        break;
      case _QuickPeriod.custom:
        setState(() => _quickPeriod = period);
        return;
    }

    setState(() {
      _quickPeriod = period;
      _startDate = start;
      _endDate = end;
    });

    if (fetch) _fetchAll();
  }

  Future<void> _fetchAll() async {
    await Future.wait([_fetchSummary(), _fetchCharts(), _fetchTransactions()]);
  }

  Future<void> _fetchTransactions() async {
    setState(() {
      _isTransactionsLoading = true;
      _transactionsError = null;
    });

    try {
      final headers = {
        'Authorization': 'Bearer ${widget.appState.authToken}',
      };

      final transactions = <OverviewTransaction>[];

      final fromDate = DateFormat('yyyy-MM-dd').format(_startDate);
      final toDate = DateFormat('yyyy-MM-dd').format(_endDate);

      final expensesPage = await _expensesService.fetchExpenses(
        page: 1,
        perPage: 100,
        headers: headers,
        fromDate: fromDate,
        toDate: toDate,
      );

      for (final expense in expensesPage.expenses) {
        if (expense.date != null &&
            expense.date!.isAfter(_startDate.subtract(const Duration(days: 1))) &&
            expense.date!.isBefore(_endDate.add(const Duration(days: 1)))) {
          transactions.add(OverviewTransaction.fromExpense(expense));
        }
      }

      if (_accountingMethod == 'payment') {
        final lookbackDate = _startDate.subtract(const Duration(days: 180));
        final lookbackFrom = DateFormat('yyyy-MM-dd').format(lookbackDate);

        final billsPage = await _billsService.fetchBills(
          page: 1,
          perPage: 100,
          headers: headers,
          fromDate: lookbackFrom,
          toDate: toDate,
        );

        for (final bill in billsPage.bills) {
          for (final payment in bill.payments) {
            if (payment.date != null &&
                payment.date!.isAfter(_startDate.subtract(const Duration(days: 1))) &&
                payment.date!.isBefore(_endDate.add(const Duration(days: 1)))) {
              transactions.add(OverviewTransaction.fromBillPayment(
                payment,
                bill.vendorName ?? 'Unknown',
                expenseName: bill.expenseName,
              ));
            }
          }

          if ((bill.status == BillStatus.paid || bill.status.code == 3) &&
              bill.payments.isEmpty) {
            try {
              final payments = await _billsService.fetchBillPayments(
                  billId: bill.id, headers: headers);
              for (final payment in payments) {
                if (payment.date != null &&
                    payment.date!.isAfter(
                        _startDate.subtract(const Duration(days: 1))) &&
                    payment.date!
                        .isBefore(_endDate.add(const Duration(days: 1)))) {
                  transactions.add(OverviewTransaction.fromBillPayment(
                    payment,
                    bill.vendorName ?? 'Unknown',
                    expenseName: bill.expenseName,
                  ));
                }
              }
            } catch (_) {}
          }
        }

        final posPage = await _purchaseOrdersService.fetchPurchaseOrders(
          page: 1,
          perPage: 100,
          headers: headers,
          fromDate: lookbackFrom,
          toDate: toDate,
        );

        final paidPos =
            posPage.orders.where((po) => (po.totalPaid ?? 0) > 0).toList();

        const int batchSize = 5;
        for (var i = 0; i < paidPos.length; i += batchSize) {
          final batch = paidPos.skip(i).take(batchSize);
          await Future.wait(batch.map((po) async {
            try {
              final details =
                  await _purchaseOrderDetailService.fetchPurchaseOrder(
                id: po.id,
                headers: headers,
              );

              for (final payment in details.payments) {
                if (payment.date != null &&
                    payment.date!.isAfter(
                        _startDate.subtract(const Duration(days: 1))) &&
                    payment.date!
                        .isBefore(_endDate.add(const Duration(days: 1)))) {
                  transactions.add(
                      OverviewTransaction.fromPurchaseOrderPayment(
                    payment,
                    po.number,
                    po.vendorName,
                    purchaseOrderName: details.name,
                  ));
                }
              }
            } catch (_) {}
          }));
        }
      } else {
        final billsPage = await _billsService.fetchBills(
          page: 1,
          perPage: 50,
          headers: headers,
          fromDate: fromDate,
          toDate: toDate,
        );
        for (final bill in billsPage.bills) {
          if (bill.billDate != null &&
              bill.billDate!
                  .isAfter(_startDate.subtract(const Duration(days: 1))) &&
              bill.billDate!
                  .isBefore(_endDate.add(const Duration(days: 1)))) {
            transactions.add(OverviewTransaction.fromBill(bill));
          }
        }

        final posPage = await _purchaseOrdersService.fetchPurchaseOrders(
          page: 1,
          perPage: 50,
          headers: headers,
          fromDate: fromDate,
          toDate: toDate,
        );
        for (final po in posPage.orders) {
          if (po.orderDate != null &&
              po.orderDate!
                  .isAfter(_startDate.subtract(const Duration(days: 1))) &&
              po.orderDate!
                  .isBefore(_endDate.add(const Duration(days: 1)))) {
            transactions.add(OverviewTransaction.fromPurchaseOrder(po));
          }
        }
      }

      transactions.sort((a, b) => b.date.compareTo(a.date));

      if (mounted) {
        setState(() {
          _transactions = transactions;
          _isTransactionsLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _transactionsError = e.toString();
          _isTransactionsLoading = false;
        });
      }
    }
  }

  Future<void> _fetchSummary() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final summary = await _service.fetchMoneyOutSummary(
        startDate: DateFormat('yyyy-MM-dd').format(_startDate),
        endDate: DateFormat('yyyy-MM-dd').format(_endDate),
        type: _accountingMethod,
        headers: {
          'Authorization': 'Bearer ${widget.appState.authToken}',
        },
      );
      if (mounted) {
        setState(() {
          _summary = summary;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _fetchCharts() async {
    setState(() {
      _isChartLoading = true;
    });

    try {
      final data = await _service.fetchExpensesPercentageByType(
        startDate: DateFormat('yyyy-MM-dd').format(_startDate),
        endDate: DateFormat('yyyy-MM-dd').format(_endDate),
        type: _accountingMethod,
        headers: {
          'Authorization': 'Bearer ${widget.appState.authToken}',
        },
      );
      if (mounted) {
        setState(() {
          _expensesPercentage = data;
          _isChartLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isChartLoading = false;
        });
      }
    }
  }

  Future<void> _selectDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
    );

    if (picked != null) {
      setState(() {
        _quickPeriod = _QuickPeriod.custom;
        _startDate = picked.start;
        _endDate = picked.end;
      });
      _fetchAll();
    }
  }

  double _parseTotal(String? total) {
    if (total == null) return 0.0;
    return double.tryParse(total) ?? 0.0;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);

    return RefreshIndicator(
      onRefresh: _fetchAll,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: _buildControls(theme)),
          SliverToBoxAdapter(child: _buildHeroCard(theme)),
          SliverToBoxAdapter(child: _buildCategoryCards(theme)),
          SliverToBoxAdapter(child: _buildCharts(theme)),
          SliverToBoxAdapter(child: _buildTransactions(theme)),
          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }

  // ── Controls: accounting method toggle + period chips ─────────────────────

  Widget _buildControls(ThemeData theme) {
    final df = DateFormat('MMM d');
    final dfYear = DateFormat('MMM d, yyyy');
    final sameYear = _startDate.year == _endDate.year;
    final rangeLabel = sameYear
        ? '${df.format(_startDate)} – ${dfYear.format(_endDate)}'
        : '${dfYear.format(_startDate)} – ${dfYear.format(_endDate)}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Accounting method pill toggle
              _MethodToggle(
                value: _accountingMethod,
                onChanged: (v) {
                  setState(() => _accountingMethod = v);
                  _fetchAll();
                },
              ),
              const Spacer(),
              // Custom date picker button
              TextButton.icon(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  foregroundColor: theme.colorScheme.onSurfaceVariant,
                ),
                icon: const Icon(Icons.calendar_today, size: 14),
                label: Text(rangeLabel, style: theme.textTheme.bodySmall),
                onPressed: _selectDateRange,
              ),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _QuickPeriod.values
                  .where((p) => p != _QuickPeriod.custom || _quickPeriod == _QuickPeriod.custom)
                  .map((p) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _PeriodChip(
                          label: _periodLabel(p),
                          selected: _quickPeriod == p,
                          onTap: () => _applyQuickPeriod(p),
                        ),
                      ))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  String _periodLabel(_QuickPeriod p) {
    switch (p) {
      case _QuickPeriod.thisMonth:
        return 'This Month';
      case _QuickPeriod.lastMonth:
        return 'Last Month';
      case _QuickPeriod.thisQuarter:
        return 'This Quarter';
      case _QuickPeriod.thisYear:
        return 'This Year';
      case _QuickPeriod.custom:
        return 'Custom';
    }
  }

  // ── Hero: total outflow ────────────────────────────────────────────────────

  Widget _buildHeroCard(ThemeData theme) {
    final isLight = theme.brightness == Brightness.light;
    final gradientStart = theme.colorScheme.primary;
    final gradientEnd = isLight
        ? const Color(0xFF4338CA)
        : theme.colorScheme.primary.withValues(alpha: 0.6);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [gradientStart, gradientEnd],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: theme.colorScheme.primary.withValues(alpha: 0.25),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: _isLoading
            ? const SizedBox(
                height: 64,
                child: Center(
                    child: CircularProgressIndicator(color: Colors.white54)),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _accountingMethod == 'payment'
                        ? 'Total Paid Out'
                        : 'Total Accrued',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _summary != null ? _summary!.totalSpent : '—',
                    style: theme.textTheme.displaySmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -1,
                    ),
                  ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _errorMessage!,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: Colors.white60),
                    ),
                  ],
                ],
              ),
      ),
    );
  }

  // ── Category KPI cards ─────────────────────────────────────────────────────

  Widget _buildCategoryCards(ThemeData theme) {
    final poTotal = _parseTotal(_summary?.purchaseOrders.total);
    final expTotal = _parseTotal(_summary?.expenses.total);
    final billTotal = _parseTotal(_summary?.bills.total);
    final grand = poTotal + expTotal + billTotal;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > 480;
          final cards = [
            _KPICard(
              label: 'Purchase Orders',
              icon: Icons.shopping_bag,
              color: _kPOColor,
              count: _summary?.purchaseOrders.count ?? 0,
              total: poTotal,
              grandTotal: grand,
              isLoading: _isLoading,
            ),
            _KPICard(
              label: 'Expenses',
              icon: Icons.payments,
              color: _kExpenseColor,
              count: _summary?.expenses.count ?? 0,
              total: expTotal,
              grandTotal: grand,
              isLoading: _isLoading,
            ),
            _KPICard(
              label: 'Bills',
              icon: Icons.receipt_long,
              color: _kBillColor,
              count: _summary?.bills.count ?? 0,
              total: billTotal,
              grandTotal: grand,
              isLoading: _isLoading,
            ),
          ];

          if (isWide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (int i = 0; i < cards.length; i++) ...[
                  Expanded(child: cards[i]),
                  if (i < cards.length - 1) const SizedBox(width: 10),
                ],
              ],
            );
          }

          return Column(
            children: [
              for (int i = 0; i < cards.length; i++) ...[
                cards[i],
                if (i < cards.length - 1) const SizedBox(height: 10),
              ],
            ],
          );
        },
      ),
    );
  }

  // ── Spending breakdown charts ──────────────────────────────────────────────

  Widget _buildCharts(ThemeData theme) {
    if (_isChartLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_expensesPercentage == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Spending Breakdown',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          _ChartsRow(
            data: _expensesPercentage!,
            accountingMethod: _accountingMethod,
          ),
        ],
      ),
    );
  }

  // ── Transaction ledger ────────────────────────────────────────────────────

  Widget _buildTransactions(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Transactions',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              if (_transactions.isNotEmpty && !_isTransactionsLoading)
                Text(
                  '${_transactions.length} records',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (_isTransactionsLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_transactionsError != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'Failed to load transactions: $_transactionsError',
                style: TextStyle(color: theme.colorScheme.error),
              ),
            )
          else if (_transactions.isNotEmpty)
            _TransactionTable(
              transactions: _transactions,
              accountingMethod: _accountingMethod,
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.receipt_long,
                        size: 48,
                        color: theme.colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.4)),
                    const SizedBox(height: 12),
                    Text(
                      'No transactions in this period',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Small reusable controls ────────────────────────────────────────────────────

class _MethodToggle extends StatelessWidget {
  const _MethodToggle({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _toggle('Cash', 'payment', theme),
          _toggle('Accrual', 'issued', theme),
        ],
      ),
    );
  }

  Widget _toggle(String label, String v, ThemeData theme) {
    final isSelected = value == v;
    return GestureDetector(
      onTap: () => onChanged(v),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? theme.colorScheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: isSelected
                ? theme.colorScheme.onPrimary
                : theme.colorScheme.onSurfaceVariant,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

class _PeriodChip extends StatelessWidget {
  const _PeriodChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
          border: selected
              ? Border.all(color: theme.colorScheme.primary, width: 1.5)
              : null,
        ),
        child: Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

// ── KPI card ──────────────────────────────────────────────────────────────────

class _KPICard extends StatelessWidget {
  const _KPICard({
    required this.label,
    required this.icon,
    required this.color,
    required this.count,
    required this.total,
    required this.grandTotal,
    required this.isLoading,
  });

  final String label;
  final IconData icon;
  final Color color;
  final int count;
  final double total;
  final double grandTotal;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pct = grandTotal > 0 ? (total / grandTotal).clamp(0.0, 1.0) : 0.0;
    final amountFmt = NumberFormat('#,##0.00');
    final pctFmt = NumberFormat('#,##0.#');

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: isLoading
            ? const SizedBox(
                height: 80,
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(icon, size: 16, color: color),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          label,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '$count',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    amountFmt.format(total),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: pct,
                      minHeight: 5,
                      backgroundColor: color.withValues(alpha: 0.12),
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${pctFmt.format(pct * 100)}% of total',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

// ── Charts row ────────────────────────────────────────────────────────────────

class _ChartsRow extends StatelessWidget {
  const _ChartsRow({required this.data, required this.accountingMethod});

  final ExpensesPieChartData data;
  final String accountingMethod;

  @override
  Widget build(BuildContext context) {
    final charts = [
      (
        title: 'By PO Item',
        items: data.purchaseOrderByItem,
        accent: _kPOColor,
      ),
      (
        title: 'By Expense Category',
        items: data.expensesByCategory,
        accent: _kExpenseColor,
      ),
      (
        title: 'By Bill Account',
        items: data.billByAccount,
        accent: _kBillColor,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 800) {
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (int i = 0; i < charts.length; i++) ...[
                  Expanded(
                    child: _DonutChartCard(
                      title: charts[i].title,
                      items: charts[i].items,
                      accent: charts[i].accent,
                      emptyLabel: accountingMethod == 'payment'
                          ? 'No payments'
                          : 'No records',
                    ),
                  ),
                  if (i < charts.length - 1) const SizedBox(width: 10),
                ],
              ],
            ),
          );
        }

        if (constraints.maxWidth >= 500) {
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            children: charts
                .map((c) => SizedBox(
                      width: (constraints.maxWidth - 10) / 2,
                      child: _DonutChartCard(
                        title: c.title,
                        items: c.items,
                        accent: c.accent,
                        emptyLabel: accountingMethod == 'payment'
                            ? 'No payments'
                            : 'No records',
                      ),
                    ))
                .toList(),
          );
        }

        return Column(
          children: charts
              .map((c) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _DonutChartCard(
                      title: c.title,
                      items: c.items,
                      accent: c.accent,
                      emptyLabel: accountingMethod == 'payment'
                          ? 'No payments'
                          : 'No records',
                    ),
                  ))
              .toList(),
        );
      },
    );
  }
}

class _DonutChartCard extends StatelessWidget {
  const _DonutChartCard({
    required this.title,
    required this.items,
    required this.accent,
    required this.emptyLabel,
  });

  final String title;
  final List<ChartItem> items;
  final Color accent;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sorted = List<ChartItem>.from(items)
      ..sort((a, b) => b.value.compareTo(a.value));
    final display = sorted.take(6).toList();
    final pctFmt = NumberFormat('#,##0.0');

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 160,
              child: sorted.isEmpty
                  ? Center(
                      child: Text(emptyLabel,
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant)))
                  : _DonutChart(items: sorted, colors: _kChartColors),
            ),
            if (display.isNotEmpty) ...[
              const SizedBox(height: 16),
              ...display.asMap().entries.map((e) {
                final color = _kChartColors[e.key % _kChartColors.length];
                final item = e.value;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          item.label.isEmpty ? 'Unknown' : item.label,
                          style: theme.textTheme.bodySmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '${pctFmt.format(item.percentage)}%',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}

class _DonutChart extends StatelessWidget {
  const _DonutChart({required this.items, required this.colors});

  final List<ChartItem> items;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => CustomPaint(
        size: Size(constraints.maxWidth, constraints.maxHeight),
        painter: _DonutPainter(items: items, colors: colors),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  const _DonutPainter({required this.items, required this.colors});

  final List<ChartItem> items;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerR = math.min(size.width, size.height) / 2;
    final innerR = outerR * 0.55;

    double total = items.fold(0, (s, i) => s + i.value);
    if (total == 0) return;

    double startAngle = -math.pi / 2;
    final gapAngle = 0.03;

    for (int i = 0; i < items.length; i++) {
      final item = items[i];
      final sweep =
          ((item.value / total) * 2 * math.pi) - gapAngle;
      if (sweep <= 0) {
        startAngle += gapAngle;
        continue;
      }

      final paint = Paint()
        ..style = PaintingStyle.fill
        ..color = colors[i % colors.length];

      final path = Path();
      final rect = Rect.fromCircle(center: center, radius: outerR);
      path.arcTo(rect, startAngle, sweep, true);

      final endAngle = startAngle + sweep;
      final innerRect = Rect.fromCircle(center: center, radius: innerR);
      path.arcTo(innerRect, endAngle, -sweep, false);
      path.close();

      canvas.drawPath(path, paint);
      startAngle += sweep + gapAngle;
    }

    // Center hole label: top item percentage
    if (items.isNotEmpty) {
      final top = items.first;
      final pctText = '${top.percentage.toStringAsFixed(0)}%';
      final topLabel = top.label.length > 10
          ? '${top.label.substring(0, 10)}…'
          : top.label;

      _drawCenterText(canvas, center, pctText, topLabel, colors[0]);
    }
  }

  void _drawCenterText(Canvas canvas, Offset center, String mainText,
      String subText, Color color) {
    final mainSpan = TextSpan(
      text: mainText,
      style: TextStyle(
        color: color,
        fontSize: 18,
        fontWeight: FontWeight.bold,
      ),
    );
    final mainPainter = TextPainter(
      text: mainSpan,
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout();
    mainPainter.paint(
      canvas,
      center.translate(-mainPainter.width / 2, -mainPainter.height - 2),
    );

    final subSpan = TextSpan(
      text: subText,
      style: const TextStyle(color: Colors.grey, fontSize: 10),
    );
    final subPainter = TextPainter(
      text: subSpan,
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout();
    subPainter.paint(
      canvas,
      center.translate(-subPainter.width / 2, 2),
    );
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) => old.items != items;
}

// ── Transaction table ─────────────────────────────────────────────────────────

enum _SortCol { date, name, vendor, type, detail, amount }

class _TransactionTable extends StatefulWidget {
  const _TransactionTable({
    required this.transactions,
    required this.accountingMethod,
  });

  final List<OverviewTransaction> transactions;
  final String accountingMethod;

  @override
  State<_TransactionTable> createState() => _TransactionTableState();
}

class _TransactionTableState extends State<_TransactionTable> {
  late List<OverviewTransaction> _sorted;
  _SortCol _sortCol = _SortCol.date;
  bool _asc = false;

  @override
  void initState() {
    super.initState();
    _sorted = List.of(widget.transactions);
    _sort(notify: false);
  }

  @override
  void didUpdateWidget(covariant _TransactionTable old) {
    super.didUpdateWidget(old);
    if (old.transactions != widget.transactions) {
      _sorted = List.of(widget.transactions);
      _sort();
    }
  }

  void _sort({bool notify = true}) {
    final s = List<OverviewTransaction>.from(_sorted)
      ..sort((a, b) {
        int c;
        switch (_sortCol) {
          case _SortCol.date:
            c = a.date.compareTo(b.date);
            break;
          case _SortCol.name:
            c = a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
            break;
          case _SortCol.vendor:
            c = a.vendor.toLowerCase().compareTo(b.vendor.toLowerCase());
            break;
          case _SortCol.type:
            c = a.type.toLowerCase().compareTo(b.type.toLowerCase());
            break;
          case _SortCol.detail:
            c = _detail(a).toLowerCase().compareTo(_detail(b).toLowerCase());
            break;
          case _SortCol.amount:
            c = a.amount.compareTo(b.amount);
            break;
        }
        return _asc ? c : -c;
      });

    if (notify) {
      setState(() => _sorted = s);
    } else {
      _sorted = s;
    }
  }

  void _tap(_SortCol col) {
    setState(() {
      if (_sortCol == col) {
        _asc = !_asc;
      } else {
        _sortCol = col;
        _asc = true;
      }
      _sort(notify: false);
    });
  }

  String _detail(OverviewTransaction t) =>
      widget.accountingMethod == 'payment'
          ? (t.paymentMode ?? t.status)
          : t.status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currencyFmt = NumberFormat('#,##0.00');
    final totalAmount =
        _sorted.fold<double>(0, (s, t) => s + t.amount);

    final table = _buildTable(theme, currencyFmt, totalAmount);

    return LayoutBuilder(
      builder: (context, constraints) {
        final content = Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: table,
          ),
        );

        if (constraints.maxWidth >= 860) return content;

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 860),
            child: content,
          ),
        );
      },
    );
  }

  Widget _buildTable(
      ThemeData theme, NumberFormat currencyFmt, double totalAmount) {
    final headerStyle = theme.textTheme.bodySmall
        ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.5);

    return Table(
      columnWidths: const {
        0: FlexColumnWidth(1.2),
        1: FlexColumnWidth(2.2),
        2: FlexColumnWidth(1.6),
        3: FlexColumnWidth(1.2),
        4: FlexColumnWidth(1.4),
        5: FlexColumnWidth(1.2),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      border: TableBorder(
        horizontalInside:
            BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      children: [
        // Header
        TableRow(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(14)),
          ),
          children: [
            _headerCell('Date', _SortCol.date, headerStyle),
            _headerCell('Name', _SortCol.name, headerStyle),
            _headerCell('Vendor', _SortCol.vendor, headerStyle),
            _headerCell('Type', _SortCol.type, headerStyle),
            _headerCell('Status / Mode', _SortCol.detail, headerStyle,
                align: TextAlign.center),
            _headerCell('Amount', _SortCol.amount, headerStyle,
                align: TextAlign.right),
          ],
        ),
        // Rows
        ..._sorted.map((t) => TableRow(
              children: [
                _cell(t.formattedDate, theme),
                _cell(t.displayName, theme),
                _cell(t.vendor, theme),
                Padding(
                  padding: const EdgeInsets.symmetric(
                      vertical: 10, horizontal: 8),
                  child: _TypeBadge(type: t.type),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                      vertical: 10, horizontal: 8),
                  child: Center(
                    child: _StatusPill(label: _detail(t), theme: theme),
                  ),
                ),
                _cell(t.formattedAmount, theme, align: TextAlign.right),
              ],
            )),
        // Total footer
        TableRow(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius:
                const BorderRadius.vertical(bottom: Radius.circular(14)),
          ),
          children: [
            _footerCell('Total', theme),
            const _EmptyCell(),
            const _EmptyCell(),
            const _EmptyCell(),
            const _EmptyCell(),
            _footerCell(currencyFmt.format(totalAmount), theme,
                align: TextAlign.right),
          ],
        ),
      ],
    );
  }

  Widget _headerCell(String text, _SortCol col, TextStyle? style,
      {TextAlign align = TextAlign.left}) {
    final isActive = _sortCol == col;
    return InkWell(
      onTap: () => _tap(col),
      child: Padding(
        padding:
            const EdgeInsets.symmetric(vertical: 11, horizontal: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: align == TextAlign.right
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          children: [
            Text(text, style: style),
            const SizedBox(width: 4),
            AnimatedOpacity(
              duration: const Duration(milliseconds: 150),
              opacity: isActive ? 1 : 0.25,
              child: Icon(
                _asc ? Icons.arrow_upward : Icons.arrow_downward,
                size: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cell(String text, ThemeData theme,
      {TextAlign align = TextAlign.left}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 8),
      child: Text(text,
          textAlign: align, style: theme.textTheme.bodySmall),
    );
  }

  Widget _footerCell(String text, ThemeData theme,
      {TextAlign align = TextAlign.left}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 8),
      child: Text(
        text,
        textAlign: align,
        style:
            theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _EmptyCell extends StatelessWidget {
  const _EmptyCell();

  @override
  Widget build(BuildContext context) => const Padding(
      padding: EdgeInsets.symmetric(vertical: 11, horizontal: 8),
      child: SizedBox.shrink());
}

class _TypeBadge extends StatelessWidget {
  const _TypeBadge({required this.type});

  final String type;

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (type.toLowerCase()) {
      'expense' => (_kExpenseColor, 'Expense'),
      'bill' => (_kBillColor, 'Bill'),
      _ => (_kPOColor, 'PO'),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.theme});

  final String label;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
      ),
    );
  }
}
