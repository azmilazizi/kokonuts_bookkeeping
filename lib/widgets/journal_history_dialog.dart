import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../app/app_state.dart';
import '../app/app_state_scope.dart';

class JournalHistoryDialog extends StatefulWidget {
  const JournalHistoryDialog({super.key, this.onEdit});

  final Future<void> Function(JournalListItem item)? onEdit;

  @override
  State<JournalHistoryDialog> createState() => _JournalHistoryDialogState();
}

class _JournalHistoryDialogState extends State<JournalHistoryDialog> {
  final _searchController = TextEditingController();
  final _accountNameFutures = <int, Future<String?>>{};
  DateTimeRange? _dateRange;
  bool _isLoading = false;
  String? _error;
  List<JournalListItem> _items = const [];
  int _currentPage = 1;
  final int _pageSize = 10;
  bool _hasNextPage = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _fetchRecords();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Map<String, String> _buildAuthHeaders(AppState appState, String token) {
    final rawToken = (appState.rawAuthToken ?? token).trim();
    final sanitizedToken =
        token.replaceFirst(RegExp('^Bearer\\s+', caseSensitive: false), '').trim();
    final normalizedAuth =
        sanitizedToken.isNotEmpty ? 'Bearer $sanitizedToken' : token.trim();
    final autoTokenValue = rawToken
        .replaceFirst(RegExp('^Bearer\\s+', caseSensitive: false), '')
        .trim();
    final authtokenHeader = autoTokenValue.isNotEmpty ? autoTokenValue : sanitizedToken;
    return {'authtoken': authtokenHeader, 'Authorization': normalizedAuth};
  }

  Future<void> _fetchRecords() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final appState = AppStateScope.of(context);
    final token = await appState.getValidAuthToken();
    if (!mounted) return;

    if (token == null || token.trim().isEmpty) {
      setState(() {
        _error = 'You are not logged in.';
        _isLoading = false;
      });
      return;
    }

    final headers = _buildAuthHeaders(appState, token);
    final queryParameters = <String, String>{
      'page': _currentPage.toString(),
      'per_page': _pageSize.toString(),
      if (_searchController.text.trim().isNotEmpty) 'search': _searchController.text.trim(),
      if (_dateRange != null) ...{
        'start_date': DateFormat('yyyy-MM-dd').format(_dateRange!.start),
        'end_date': DateFormat('yyyy-MM-dd').format(_dateRange!.end),
      },
      if ((headers['authtoken'] ?? '').isNotEmpty) 'authkey': headers['authtoken']!,
    };

    final uri = Uri.parse(
      'https://crm.kokonuts.my/accounting/api/v1/journal_entries_and_transfers',
    ).replace(queryParameters: queryParameters);

    http.Response response;
    final client = http.Client();
    try {
      response = await client.get(uri, headers: headers);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load records: $error';
          _isLoading = false;
        });
      }
      return;
    } finally {
      client.close();
    }

    if (response.statusCode != 200) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load records (${response.statusCode})';
          _isLoading = false;
        });
      }
      return;
    }

    final parsed = jsonDecode(response.body);
    final records = _extractList(parsed).map(JournalListItem.fromMap).toList();

    if (!mounted) return;

    setState(() {
      _items = records;
      _hasNextPage = _determineHasMore(parsed, records.length);
      _isLoading = false;
    });
  }

  List<Map<String, dynamic>> _extractList(dynamic parsed) {
    dynamic data = parsed;
    if (parsed is Map<String, dynamic>) {
      data = parsed['data'] ?? parsed['result'] ?? parsed['items'] ?? parsed;
      if (data is Map<String, dynamic>) {
        data = data['data'] ?? data['items'] ?? data['list'] ??
            data.values.firstWhere((value) => value is List, orElse: () => data);
      }
    }

    if (data is List) {
      return data.whereType<Map<String, dynamic>>().toList();
    }

    return const [];
  }

  bool _determineHasMore(dynamic parsed, int recordCount) {
    if (parsed is Map<String, dynamic>) {
      final pagination = parsed['pagination'] ?? parsed['meta'] ?? parsed['result'];
      if (pagination is Map<String, dynamic>) {
        final currentPage = _asInt(
              pagination['page'] ?? pagination['current_page'],
            ) ??
            _currentPage;
        final totalPages = _asInt(pagination['total_pages'] ?? pagination['last_page']);
        if (totalPages != null) {
          return currentPage < totalPages;
        }
      }
    }
    return recordCount >= _pageSize;
  }

  int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
      initialDateRange: _dateRange,
    );

    if (range != null) {
      setState(() {
        _dateRange = range;
        _currentPage = 1;
      });
      await _fetchRecords();
    }
  }

  void _clearDateFilter() {
    setState(() {
      _dateRange = null;
      _currentPage = 1;
    });
    _fetchRecords();
  }

  Future<String?> _accountName(int? id) {
    if (id == null) {
      return Future.value(null);
    }

    return _accountNameFutures.putIfAbsent(id, () => _loadAccountName(id));
  }

  Future<String?> _loadAccountName(int id) async {
    final appState = AppStateScope.of(context);
    final token = await appState.getValidAuthToken();
    if (!mounted) return null;
    if (token == null || token.trim().isEmpty) {
      return 'Account $id';
    }

    final headers = _buildAuthHeaders(appState, token);
    final uri = Uri.parse(
      'https://crm.kokonuts.my/accounting/api/v1/account/$id',
    ).replace(queryParameters: {
      if ((headers['authtoken'] ?? '').isNotEmpty) 'authkey': headers['authtoken']!,
    });

    try {
      final response = await http.get(uri, headers: headers);
      if (response.statusCode != 200) {
        return 'Account $id';
      }

      final decoded = jsonDecode(response.body);
      final data = decoded is Map<String, dynamic>
          ? decoded['data'] ?? decoded['result'] ?? decoded
          : decoded;

      if (data is Map<String, dynamic>) {
        final name = data['name'] ?? data['account_name'] ?? data['label'];
        if (name != null && name.toString().isNotEmpty) {
          return name.toString();
        }
      }
    } catch (_) {
      return 'Account $id';
    }

    return 'Account $id';
  }

  Future<void> _deleteRecord(JournalListItem item) async {
    final id = item.id;
    if (id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to delete item without an id.')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete record'),
        content: Text('Are you sure you want to delete ${item.number ?? 'this record'}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    final appState = AppStateScope.of(context);
    final token = await appState.getValidAuthToken();
    if (!mounted) return;

    if (token == null || token.trim().isEmpty) {
      setState(() {
        _error = 'You are not logged in.';
        _isLoading = false;
      });
      return;
    }

    final headers = _buildAuthHeaders(appState, token);
    final endpoint = item.type == 'transfer'
        ? 'https://crm.kokonuts.my/accounting/api/v1/transfers'
        : 'https://crm.kokonuts.my/accounting/api/v1/journal_entries';

    final uri = Uri.parse('$endpoint/$id').replace(queryParameters: {
      if ((headers['authtoken'] ?? '').isNotEmpty) 'authkey': headers['authtoken']!,
    });

    http.Response response;
    final client = http.Client();
    try {
      response = await client.delete(uri, headers: headers);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = 'Failed to delete record: $error';
          _isLoading = false;
        });
      }
      return;
    } finally {
      client.close();
    }

    if (response.statusCode != 200 && response.statusCode != 204) {
      if (mounted) {
        setState(() {
          _error = 'Unable to delete record (${response.statusCode}).';
          _isLoading = false;
        });
      }
      return;
    }

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${item.displayType} deleted successfully.')),
    );

    await _fetchRecords();
  }

  Future<void> _editRecord(JournalListItem item) async {
    if (widget.onEdit == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Editing is not available right now.')),
      );
      return;
    }

    await widget.onEdit!();
    await _fetchRecords();
  }

  void _applySearch() {
    setState(() {
      _currentPage = 1;
    });
    _fetchRecords();
  }

  void _previousPage() {
    if (_currentPage <= 1 || _isLoading) return;
    setState(() {
      _currentPage -= 1;
    });
    _fetchRecords();
  }

  void _nextPage() {
    if (!_hasNextPage || _isLoading) return;
    setState(() {
      _currentPage += 1;
    });
    _fetchRecords();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final dialogWidth = (screenSize.width * 0.92).clamp(420.0, 840.0);
    final dialogHeight = (screenSize.height * 0.88).clamp(420.0, screenSize.height);

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 12, 0),
      title: Row(
        children: [
          const Expanded(
            child: Text(
              'View Journal Entry and Transfers',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          IconButton(
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      content: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Column(
          children: [
            _buildFilters(),
            const SizedBox(height: 12),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(_error!, style: const TextStyle(color: Colors.red)),
                ),
              ),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _items.isEmpty
                      ? const Center(
                          child: Text(
                            'No journal entries or transfers found. Please create a new entry first.',
                            textAlign: TextAlign.center,
                          ),
                        )
                      : Scrollbar(
                          thumbVisibility: true,
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final tableWidth = constraints.maxWidth < 760
                                  ? 760.0
                                  : constraints.maxWidth;

                              return SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(minWidth: tableWidth),
                                  child: SingleChildScrollView(
                                    child: DataTable(
                                      columnSpacing: 18,
                                      columns: const [
                                        DataColumn(label: Text('Description')),
                                        DataColumn(label: Text('Credit Account')),
                                        DataColumn(label: Text('Debit Account')),
                                        DataColumn(label: Text('Amount')),
                                        DataColumn(label: Text('Type')),
                                        DataColumn(label: Text('Actions')),
                                      ],
                                      rows: _items
                                          .map(
                                            (item) => DataRow(
                                              cells: [
                                                DataCell(Text(
                                                    item.description ?? item.number ?? '-')),
                                                DataCell(_AccountNameCell(
                                                  fetcher: _accountName,
                                                  accountId: item.creditAccountId,
                                                )),
                                                DataCell(_AccountNameCell(
                                                  fetcher: _accountName,
                                                  accountId: item.debitAccountId,
                                                )),
                                                DataCell(Text(item.amountLabel)),
                                                DataCell(
                                                  Center(
                                                    child: Container(
                                                      padding: const EdgeInsets.symmetric(
                                                        horizontal: 10,
                                                        vertical: 6,
                                                      ),
                                                      decoration: BoxDecoration(
                                                        color: Colors.blue
                                                            .withOpacity(0.08),
                                                        borderRadius: BorderRadius.circular(20),
                                                      ),
                                                      child: Text(
                                                        item.displayType,
                                                        style: const TextStyle(
                                                          fontWeight: FontWeight.w600,
                                                          color: Colors.blue,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                DataCell(
                                                  Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      IconButton(
                                                        key: ValueKey('edit_${item.id}'),
                                                        tooltip: 'Edit',
                                                        icon: const Icon(
                                                            Icons.edit_outlined),
                                                        onPressed: () => _editRecord(item),
                                                      ),
                                                      IconButton(
                                                        key: ValueKey('delete_${item.id}'),
                                                        tooltip: 'Delete',
                                                        icon: const Icon(
                                                            Icons.delete_outline),
                                                        onPressed: () => _deleteRecord(item),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          )
                                          .toList(),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
            ),
            const SizedBox(height: 8),
            _buildPagination(),
          ],
        ),
      ),
    );
  }

  Widget _buildFilters() {
    final dateLabel = _dateRange != null
        ? '${DateFormat('yyyy-MM-dd').format(_dateRange!.start)} - ${DateFormat('yyyy-MM-dd').format(_dateRange!.end)}'
        : 'Select date range';

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  labelText: 'Search',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _searchController.clear();
                      _applySearch();
                    },
                  ),
                ),
                onSubmitted: (_) => _applySearch(),
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: _pickDateRange,
              icon: const Icon(Icons.event),
              label: Text(dateLabel),
            ),
            if (_dateRange != null)
              IconButton(
                tooltip: 'Clear date filter',
                onPressed: _clearDateFilter,
                icon: const Icon(Icons.close),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildPagination() {
    return Row(
      children: [
        Text('Page $_currentPage'),
        const Spacer(),
        IconButton(
          onPressed: _currentPage > 1 && !_isLoading ? _previousPage : null,
          icon: const Icon(Icons.chevron_left),
        ),
        IconButton(
          onPressed: _hasNextPage && !_isLoading ? _nextPage : null,
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }
}

class _AccountNameCell extends StatelessWidget {
  const _AccountNameCell({required this.fetcher, required this.accountId});

  final Future<String?> Function(int? id) fetcher;
  final int? accountId;

  @override
  Widget build(BuildContext context) {
    if (accountId == null) {
      return const Text('-');
    }

    return FutureBuilder<String?>(
      future: fetcher(accountId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            height: 18,
            width: 90,
            child: LinearProgressIndicator(minHeight: 3),
          );
        }

        return Text(snapshot.data ?? 'Account ${accountId ?? ''}');
      },
    );
  }
}

class JournalListItem {
  JournalListItem({
    required this.id,
    required this.number,
    required this.creditAccountId,
    required this.debitAccountId,
    required this.amount,
    required this.type,
    this.description,
    this.date,
    this.entryId,
  });

  final dynamic id;
  final String? number;
  final int? creditAccountId;
  final int? debitAccountId;
  final double? amount;
  final String? type;
  final String? description;
  final DateTime? date;
  final String? entryId;

  static final _amountFormat = NumberFormat('#,##0.00');

  String get displayType {
    if (type == null || type!.isEmpty) return '-';
    final words = type!.split('_').where((word) => word.isNotEmpty).map(
          (word) => '${word[0].toUpperCase()}${word.substring(1)}',
        );
    final value = words.join(' ');
    return value.isNotEmpty ? value : type!;
  }

  String get amountLabel {
    if (amount == null) return '-';
    return _amountFormat.format(amount);
  }

  bool get isTransfer =>
      (type ?? '').toLowerCase() == 'transfer' ||
      (type ?? '').toLowerCase() == 'cash_deposit' ||
      (type ?? '').toLowerCase() == 'cash_withdrawal';

  factory JournalListItem.fromMap(Map<String, dynamic> map) {
    final data = map['data'];
    final source = data is Map<String, dynamic> ? data : map;
    final type = (source['type'] ?? map['type'])?.toString();
    return JournalListItem(
      id: source['id'] ?? map['journal_entry_id'] ?? map['transfer_id'],
      number: source['number']?.toString() ?? source['description']?.toString(),
      creditAccountId: _asInt(
          source['credit_account'] ?? source['transfer_funds_from'] ?? source['credit']),
      debitAccountId: _asInt(
          source['debit_account'] ?? source['transfer_funds_to'] ?? source['debit']),
      amount: _asDouble(
          source['amount'] ?? source['transfer_amount'] ?? source['total']),
      type: type,
      description: source['description']?.toString(),
      entryId: source['entry_id']?.toString() ?? source['number']?.toString(),
      date: _parseDate(source['date'] ?? source['created_at']),
    );
  }

  static int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static double? _asDouble(dynamic value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  static DateTime? _parseDate(dynamic value) {
    if (value is DateTime) return value;
    if (value is String) {
      return DateTime.tryParse(value);
    }
    return null;
  }
}
