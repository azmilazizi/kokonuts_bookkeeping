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

class OverviewTab extends StatefulWidget {
  const OverviewTab({super.key, required this.appState});

  final AppState appState;

  @override
  State<OverviewTab> createState() => _OverviewTabState();
}

class _OverviewTabState extends State<OverviewTab> {
  late final OverviewService _service;
  late final ExpensesService _expensesService;
  late final BillsService _billsService;
  late final PurchaseOrdersService _purchaseOrdersService;
  late final PurchaseOrderDetailService _purchaseOrderDetailService;
  final ScrollController _tableHorizontalController = ScrollController();

  late DateTime _startDate;
  late DateTime _endDate;

  bool _isLoading = false;
  bool _isChartLoading = false;
  bool _isTransactionsLoading = false;
  String? _errorMessage;
  String? _transactionsError;
  MoneyOutSummary? _summary;
  ExpensesPieChartData? _expensesPercentage;
  String _accountingMethod = 'payment'; // 'payment' (Cash) or 'issued' (Accrual)
  List<OverviewTransaction> _transactions = [];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _startDate = DateTime(now.year, now.month, 1);
    // Last day of current month: 0th day of next month
    _endDate = DateTime(now.year, now.month + 1, 0);

    _service = OverviewService();
    _expensesService = ExpensesService();
    _billsService = BillsService();
    _purchaseOrdersService = PurchaseOrdersService();
    _purchaseOrderDetailService = PurchaseOrderDetailService();

    _fetchSummary();
    _fetchCharts();
    _fetchTransactions();
  }

  @override
  void dispose() {
    _tableHorizontalController.dispose();
    super.dispose();
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

      // Fetch Expenses (common for both methods)
      final expensesPage = await _expensesService.fetchExpenses(
        page: 1,
        perPage: 100, // Fetch more to be safe
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
        // Cash Accounting:
        // 1. Fetch Bills from a wider range (6 months back) to catch recent payments on old bills
        // 2. Fetch Purchase Orders from a wider range and get their payments

        final lookbackDate = _startDate.subtract(const Duration(days: 180));
        final lookbackFrom = DateFormat('yyyy-MM-dd').format(lookbackDate);

        // --- BILLS ---
        final billsPage = await _billsService.fetchBills(
          page: 1,
          perPage: 100,
          headers: headers,
          fromDate: lookbackFrom,
          toDate: toDate,
        );

        for (final bill in billsPage.bills) {
          // Check existing payments in the bill object
          for (final payment in bill.payments) {
             if (payment.date != null &&
                payment.date!.isAfter(_startDate.subtract(const Duration(days: 1))) &&
                payment.date!.isBefore(_endDate.add(const Duration(days: 1)))) {
                transactions.add(OverviewTransaction.fromBillPayment(
                  payment,
                  bill.vendorName ?? 'Unknown'
                ));
             }
          }

          // If bill is paid or partially paid but payments list is empty or suspicious,
          // we might want to fetch details. However, memory says "fetching missing payment details in batches".
          // For now, let's rely on what's returned or strictly what's in `payments`.
          // If we need to fetch individual bill payments, we can do it here.
          // The previous code didn't fetch individual payments, so we'll stick to bill.payments for now unless users complain or logic demands it.
          // Wait, memory says: "To reliably display bill payments, the application fetches individual payment details via BillsService.fetchBillPayments(billId) for bills marked as 'Paid' or 'Partially Paid'."
          if ((bill.status == BillStatus.paid || bill.status.code == 3) && bill.payments.isEmpty) { // 3 is partial usually?
             try {
               final payments = await _billsService.fetchBillPayments(billId: bill.id, headers: headers);
               for (final payment in payments) {
                 if (payment.date != null &&
                    payment.date!.isAfter(_startDate.subtract(const Duration(days: 1))) &&
                    payment.date!.isBefore(_endDate.add(const Duration(days: 1)))) {
                    transactions.add(OverviewTransaction.fromBillPayment(
                      payment,
                      bill.vendorName ?? 'Unknown'
                    ));
                 }
               }
             } catch (_) {
               // Ignore errors fetching details
             }
          }
        }

        // --- PURCHASE ORDERS ---
        final posPage = await _purchaseOrdersService.fetchPurchaseOrders(
          page: 1,
          perPage: 100,
          headers: headers,
          fromDate: lookbackFrom,
          toDate: toDate,
        );

        // Filter POs that have some payment made
        final paidPos = posPage.orders.where((po) => (po.totalPaid ?? 0) > 0).toList();

        // Fetch details for these POs to get payment records
        // Process in batches of 5 to avoid overwhelming the server
        const int batchSize = 5;
        for (var i = 0; i < paidPos.length; i += batchSize) {
          final batch = paidPos.skip(i).take(batchSize);
          await Future.wait(batch.map((po) async {
            try {
              final details = await _purchaseOrderDetailService.fetchPurchaseOrder(
                id: po.id,
                headers: headers,
              );

              for (final payment in details.payments) {
                if (payment.date != null &&
                    payment.date!.isAfter(_startDate.subtract(const Duration(days: 1))) &&
                    payment.date!.isBefore(_endDate.add(const Duration(days: 1)))) {
                  transactions.add(OverviewTransaction.fromPurchaseOrderPayment(
                    payment,
                    po.number,
                    po.vendorName,
                  ));
                }
              }
            } catch (_) {
              // Ignore errors fetching details
            }
          }));
        }

      } else {
        // Accrual Accounting (Issued)
        final billsPage = await _billsService.fetchBills(
          page: 1,
          perPage: 50,
          headers: headers,
          fromDate: fromDate,
          toDate: toDate,
        );
         for (final bill in billsPage.bills) {
             if (bill.billDate != null &&
                bill.billDate!.isAfter(_startDate.subtract(const Duration(days: 1))) &&
                bill.billDate!.isBefore(_endDate.add(const Duration(days: 1)))) {
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
                po.orderDate!.isAfter(_startDate.subtract(const Duration(days: 1))) &&
                po.orderDate!.isBefore(_endDate.add(const Duration(days: 1)))) {
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
        _startDate = picked.start;
        _endDate = picked.end;
      });
      _fetchSummary();
      _fetchCharts();
      _fetchTransactions();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateFormatter = DateFormat('MMM dd, yyyy');

    return RefreshIndicator(
      onRefresh: () async {
        await _fetchSummary();
        await _fetchCharts();
        await _fetchTransactions();
      },
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Accounting Method: ',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onPrimaryContainer,
                              ),
                            ),
                            const SizedBox(width: 8),
                            DropdownButton<String>(
                              value: _accountingMethod,
                              dropdownColor: theme.colorScheme.primaryContainer,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onPrimaryContainer,
                                fontWeight: FontWeight.bold,
                              ),
                              underline: Container(
                                height: 1,
                                color: theme.colorScheme.onPrimaryContainer,
                              ),
                              icon: Icon(
                                Icons.arrow_drop_down,
                                color: theme.colorScheme.onPrimaryContainer,
                              ),
                              onChanged: (String? newValue) {
                                if (newValue != null) {
                                  setState(() {
                                    _accountingMethod = newValue;
                                  });
                                  _fetchCharts();
                                  _fetchSummary();
                                  _fetchTransactions();
                                }
                              },
                              items: const [
                                DropdownMenuItem(
                                  value: 'payment',
                                  child: Text('Cash'),
                                ),
                                DropdownMenuItem(
                                  value: 'issued',
                                  child: Text('Accrual'),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        InkWell(
                          onTap: _selectDateRange,
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 8.0,
                              horizontal: 4.0,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.calendar_today,
                                  size: 16,
                                  color: theme.colorScheme.onPrimaryContainer,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '${dateFormatter.format(_startDate)} - ${dateFormatter.format(_endDate)}',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    color: theme.colorScheme.onPrimaryContainer,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Icon(
                                  Icons.arrow_drop_down,
                                  color: theme.colorScheme.onPrimaryContainer,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        Text(
                          'Total Spent',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: theme.colorScheme.onPrimaryContainer.withOpacity(0.8),
                          ),
                        ),
                        const SizedBox(height: 4),
                        if (_isLoading)
                          Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: SizedBox(
                              height: 24,
                              width: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: theme.colorScheme.onPrimaryContainer,
                              ),
                            ),
                          )
                        else if (_summary != null)
                          Text(
                            _summary!.totalSpent,
                            style: theme.textTheme.headlineLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          )
                        else
                          Text(
                            '--',
                            style: theme.textTheme.headlineLarge?.copyWith(
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  Text(
                    'Transaction Summary',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),

                  if (_errorMessage != null)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32.0),
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(color: theme.colorScheme.error),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  else if (_summary != null)
                    _TransactionSummarySection(summary: _summary!)
                  else if (!_isLoading)
                    const Center(child: Text('No data available')),

                  const SizedBox(height: 32),

                  Text(
                    'Transactions by Type',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_isChartLoading)
                    const Center(child: CircularProgressIndicator())
                  else if (_expensesPercentage != null)
                    _ExpensesByTypeSection(data: _expensesPercentage!, accountingMethod: _accountingMethod)
                  else
                    const Center(child: Text('No chart data available')),

                  const SizedBox(height: 32),

                  Text(
                    'Transaction Details',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),

          if (_isTransactionsLoading)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_transactionsError != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'Failed to load transactions: $_transactionsError',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            )
          else if (_transactions.isNotEmpty)
            SliverToBoxAdapter(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  const double minTableWidth = 900;
                  final tableWidth = math.max(constraints.maxWidth, minTableWidth);

                  return Scrollbar(
                    controller: _tableHorizontalController,
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      controller: _tableHorizontalController,
                      scrollDirection: Axis.horizontal,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minWidth: tableWidth),
                        child: Column(
                          children: [
                            _TableHeaderRow(
                              theme: theme,
                              tableWidth: tableWidth,
                            ),
                            ..._transactions.map(
                              (transaction) => _TransactionRow(
                                transaction: transaction,
                                theme: theme,
                                tableWidth: tableWidth,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            )
          else
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Text('No transactions found in this period.'),
              ),
            ),

          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }
}

class _TableHeaderRow extends StatelessWidget {
  const _TableHeaderRow({
    required this.theme,
    required this.tableWidth,
  });

  final ThemeData theme;
  final double tableWidth;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      constraints: BoxConstraints.tightFor(width: tableWidth),
      child: Row(
        children: const [
          Expanded(flex: 2, child: Text('Date', style: TextStyle(fontWeight: FontWeight.bold))),
          Expanded(flex: 2, child: Text('Number', style: TextStyle(fontWeight: FontWeight.bold))),
          Expanded(flex: 3, child: Text('Vendor', style: TextStyle(fontWeight: FontWeight.bold))),
          Expanded(flex: 2, child: Text('Type', style: TextStyle(fontWeight: FontWeight.bold))),
          Expanded(flex: 2, child: Text('Mode / Status', style: TextStyle(fontWeight: FontWeight.bold))),
          Expanded(flex: 2, child: Text('Amount', style: TextStyle(fontWeight: FontWeight.bold))),
        ],
      ),
    );
  }
}

class _TransactionRow extends StatelessWidget {
  const _TransactionRow({
    required this.transaction,
    required this.theme,
    required this.tableWidth,
  });

  final OverviewTransaction transaction;
  final ThemeData theme;
  final double tableWidth;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.dividerColor.withOpacity(0.5))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      constraints: BoxConstraints.tightFor(width: tableWidth),
      child: Row(
        children: [
          Expanded(flex: 2, child: Text(transaction.formattedDate, style: theme.textTheme.bodyMedium)),
          Expanded(flex: 2, child: Text(transaction.number, style: theme.textTheme.bodyMedium)),
          Expanded(flex: 3, child: Text(transaction.vendor, style: theme.textTheme.bodyMedium)),
          Expanded(flex: 2, child: Text(transaction.type, style: theme.textTheme.bodyMedium)),
          Expanded(flex: 2, child: Text(transaction.paymentMode ?? transaction.status, style: theme.textTheme.bodyMedium)),
          Expanded(flex: 2, child: Text(transaction.formattedAmount, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

class _TransactionSummarySection extends StatelessWidget {
  const _TransactionSummarySection({required this.summary});

  final MoneyOutSummary summary;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isLargeScreen = constraints.maxWidth > 600;

        final cards = [
          _SummaryCard(
            title: 'Purchase Orders',
            count: summary.purchaseOrders.count,
            total: summary.purchaseOrders.total,
            icon: Icons.shopping_cart,
          ),
          _SummaryCard(
            title: 'Expenses',
            count: summary.expenses.count,
            total: summary.expenses.total,
            icon: Icons.receipt,
          ),
          _SummaryCard(
            title: 'Bills',
            count: summary.bills.count,
            total: summary.bills.total,
            icon: Icons.description,
          ),
        ];

        if (isLargeScreen) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: cards.map((c) => Expanded(child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
              child: c,
            ))).toList(),
          );
        } else {
          return Column(
            children: cards.map((c) => Padding(
              padding: const EdgeInsets.only(bottom: 12.0),
              child: c,
            )).toList(),
          );
        }
      },
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.title,
    required this.count,
    required this.total,
    required this.icon,
  });

  final String title;
  final int count;
  final String total;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Number of Transaction',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.textTheme.bodySmall?.color,
                  ),
                ),
                Text(
                  '$count',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Total Spent',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.textTheme.bodySmall?.color,
                  ),
                ),
                Text(
                  total,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ExpensesByTypeSection extends StatelessWidget {
  const _ExpensesByTypeSection({required this.data, required this.accountingMethod});

  final ExpensesPieChartData data;
  final String accountingMethod;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isLargeScreen = constraints.maxWidth > 900;
        final isMediumScreen = constraints.maxWidth > 600;

        final charts = [
          _PieChartCard(
            title: 'Purchase Order by Item',
            items: data.purchaseOrderByItem,
            accountingMethod: accountingMethod,
          ),
          _PieChartCard(
            title: 'Expenses by Category',
            items: data.expensesByCategory,
            accountingMethod: accountingMethod,
          ),
          _PieChartCard(
            title: 'Bill by Account',
            items: data.billByAccount,
            accountingMethod: accountingMethod,
          ),
        ];

        if (isLargeScreen) {
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: charts.map((c) => Expanded(child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: c,
              ))).toList(),
            ),
          );
        } else if (isMediumScreen) {
          return Wrap(
            spacing: 16,
            runSpacing: 16,
            children: charts.map((c) => SizedBox(
              width: (constraints.maxWidth - 32) / 2,
              child: c,
            )).toList(),
          );
        } else {
          return Column(
            children: charts.map((c) => Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              child: c,
            )).toList(),
          );
        }
      },
    );
  }
}

class _PieChartCard extends StatelessWidget {
  const _PieChartCard({
    required this.title,
    required this.items,
    required this.accountingMethod,
  });

  final String title;
  final List<ChartItem> items;
  final String accountingMethod;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currencyFormat = NumberFormat.simpleCurrency(name: '');
    final sortedItems = List<ChartItem>.from(items)
      ..sort((a, b) => b.value.compareTo(a.value));

    final displayItems = sortedItems.take(5).toList();

    final noDataMessage = accountingMethod == 'payment' ? 'No Payment' : 'No Outstanding';

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 200,
              width: double.infinity,
              child: items.isEmpty
                  ? Center(child: Text(noDataMessage, style: theme.textTheme.bodyMedium))
                  : _PieChart(
                      items: items,
                      colors: const [
                        Colors.blue,
                        Colors.red,
                        Colors.green,
                        Colors.orange,
                        Colors.purple,
                        Colors.teal,
                        Colors.pink,
                        Colors.amber,
                        Colors.indigo,
                        Colors.cyan,
                      ],
                    ),
            ),
            const SizedBox(height: 24),
            if (displayItems.isNotEmpty)
              Column(
                children: displayItems.asMap().entries.map((entry) {
                  final index = entry.key;
                  final item = entry.value;
                  final color = [
                    Colors.blue,
                    Colors.red,
                    Colors.green,
                    Colors.orange,
                    Colors.purple,
                    Colors.teal,
                    Colors.pink,
                    Colors.amber,
                    Colors.indigo,
                    Colors.cyan,
                  ][index % 10];

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4.0),
                    child: Row(
                      children: [
                        Container(
                          width: 12,
                          height: 12,
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
                          currencyFormat.format(item.value),
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }
}

class _PieChart extends StatelessWidget {
  final List<ChartItem> items;
  final List<Color> colors;

  const _PieChart({
    required this.items,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return CustomPaint(
          size: size,
          painter: _PieChartPainter(
            items: items,
            colors: colors,
          ),
        );
      },
    );
  }
}

class _PieChartPainter extends CustomPainter {
  final List<ChartItem> items;
  final List<Color> colors;

  _PieChartPainter({
    required this.items,
    required this.colors,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;
    final paint = Paint()..style = PaintingStyle.fill;

    double startAngle = -math.pi / 2;
    double totalValue = items.fold(0, (sum, item) => sum + item.value);

    if (totalValue == 0) return;

    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      final sweepAngle = (item.value / totalValue) * 2 * math.pi;

      paint.color = colors[i % colors.length];

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        true,
        paint,
      );

      if (item.percentage >= 5) {
        final middleAngle = startAngle + sweepAngle / 2;
        final textRadius = radius * 0.7;
        final dx = center.dx + textRadius * math.cos(middleAngle);
        final dy = center.dy + textRadius * math.sin(middleAngle);

        final percentageText = '${item.percentage.toStringAsFixed(0)}%';

        final textSpan = TextSpan(
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
            shadows: [
              Shadow(blurRadius: 2, color: Colors.black45, offset: Offset(1, 1))
            ],
          ),
          text: percentageText,
        );

        final textPainter = TextPainter(
          text: textSpan,
          textAlign: TextAlign.center,
          textDirection: TextDirection.ltr,
        );

        textPainter.layout();

        final offset = Offset(
          dx - textPainter.width / 2,
          dy - textPainter.height / 2,
        );

        textPainter.paint(canvas, offset);
      }

      startAngle += sweepAngle;
    }
  }

  @override
  bool shouldRepaint(covariant _PieChartPainter oldDelegate) {
    return oldDelegate.items != items;
  }
}
