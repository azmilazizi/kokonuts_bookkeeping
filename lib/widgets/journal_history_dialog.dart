import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../app/app_state.dart';
import '../app/app_state_scope.dart';

class JournalHistoryDialog extends StatefulWidget {
  const JournalHistoryDialog({super.key});

  @override
  State<JournalHistoryDialog> createState() => _JournalHistoryDialogState();
}

class _JournalHistoryDialogState extends State<JournalHistoryDialog> {
  late final Future<List<_JournalRecord>> _recordsFuture;

  @override
  void initState() {
    super.initState();
    _recordsFuture = _loadRecords();
  }

  Future<List<_JournalRecord>> _loadRecords() async {
    final appState = AppStateScope.of(context);
    final token = await appState.getValidAuthToken();
    if (token == null || token.trim().isEmpty) {
      throw Exception('You are not logged in.');
    }

    final headers = _buildAuthHeaders(appState, token);
    final authKey = headers['authtoken'];

    final authQuery = {
      if (authKey != null && authKey.isNotEmpty) 'authkey': authKey,
    };

    final entriesUri = Uri.parse(
      'https://crm.kokonuts.my/accounting/api/v1/journal_entries',
    ).replace(queryParameters: authQuery);

    final transfersUri = Uri.parse(
      'https://crm.kokonuts.my/accounting/api/v1/transfers',
    ).replace(queryParameters: authQuery);

    final client = http.Client();
    try {
      final responses = await Future.wait([
        client.get(entriesUri, headers: headers),
        client.get(transfersUri, headers: headers),
      ]);

      final journalEntries = _parseList(responses[0]);
      final transfers = _parseList(responses[1]);

      final records = <_JournalRecord>[
        ...journalEntries.map(
          (entry) => _JournalRecord.fromData(entry, _JournalRecordType.entry),
        ),
        ...transfers.map(
          (entry) => _JournalRecord.fromData(entry, _JournalRecordType.transfer),
        ),
      ];

      records.sort((a, b) {
        final dateA = a.date ?? DateTime.fromMillisecondsSinceEpoch(0);
        final dateB = b.date ?? DateTime.fromMillisecondsSinceEpoch(0);
        return dateB.compareTo(dateA);
      });

      return records;
    } finally {
      client.close();
    }
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

  List<Map<String, dynamic>> _parseList(http.Response response) {
    if (response.statusCode != 200) {
      throw Exception('Failed to load data (${response.statusCode})');
    }

    final decoded = jsonDecode(response.body);
    final data = decoded is Map<String, dynamic> ? decoded['data'] ?? decoded : decoded;

    if (data is List) {
      return data.cast<Map<String, dynamic>>();
    }

    throw Exception('Unexpected response format');
  }

  void _showRecordDetails(_JournalRecord record) {
    final entries = record.raw.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('${record.type.label} Details'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Reference: ${record.reference ?? '-'}'),
                  const SizedBox(height: 8),
                  Text('Date: ${record.formattedDate ?? '-'}'),
                  const SizedBox(height: 8),
                  Text('Amount: ${record.amount ?? '-'}'),
                  const SizedBox(height: 8),
                  Text('Description: ${record.description ?? '-'}'),
                  const Divider(height: 24),
                  ...entries.map(
                    (entry) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text('${entry.key}: ${entry.value}'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Delete'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Edit'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final dialogWidth = (MediaQuery.of(context).size.width * 0.92).clamp(420.0, 840.0);

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 12, 0),
      title: Row(
        children: [
          const Expanded(
            child: Text(
              'Journal Entries & Transfers',
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
        child: FutureBuilder<List<_JournalRecord>>(
          future: _recordsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text('Unable to load records: ${snapshot.error}'),
              );
            }

            final records = snapshot.data ?? const [];
            if (records.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('No journal entries or transfers found.'),
              );
            }

            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 620),
                child: SingleChildScrollView(
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('Type')),
                      DataColumn(label: Text('Reference')),
                      DataColumn(label: Text('Date')),
                      DataColumn(label: Text('Amount')),
                      DataColumn(label: Text('Description')),
                    ],
                    rows: records
                        .map(
                          (record) => DataRow(
                            cells: [
                              DataCell(Text(record.type.label)),
                              DataCell(Text(record.reference ?? '-')),
                              DataCell(Text(record.formattedDate ?? '-')),
                              DataCell(Text(record.amount ?? '-')),
                              DataCell(Text(record.description ?? '-')),
                            ],
                            onSelectChanged: (selected) {
                              if (selected == true) {
                                _showRecordDetails(record);
                              }
                            },
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
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _JournalRecord {
  _JournalRecord({
    required this.type,
    required this.raw,
    this.reference,
    this.amount,
    this.description,
    this.date,
  });

  final _JournalRecordType type;
  final Map<String, dynamic> raw;
  final String? reference;
  final String? amount;
  final String? description;
  final DateTime? date;

  String? get formattedDate =>
      date != null ? DateFormat('yyyy-MM-dd').format(date!) : raw['date']?.toString();

  static _JournalRecord fromData(Map<String, dynamic> data, _JournalRecordType type) {
    return _JournalRecord(
      type: type,
      raw: data,
      reference: _firstNonEmpty(
        data, const ['reference', 'reference_no', 'id', 'journal_entry_id', 'transfer_id'],
      ),
      amount: _firstNonEmpty(data, const ['amount', 'total', 'transfer_amount', 'debit', 'credit']),
      description: _firstNonEmpty(
        data,
        const ['description', 'note', 'memo', 'remarks'],
      ),
      date: _parseDate(
        _firstNonEmpty(
          data,
          const ['date', 'journal_date', 'transfer_date', 'created_at'],
        ),
      ),
    );
  }

  static String? _firstNonEmpty(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];
      if (value == null) continue;
      final stringValue = value.toString();
      if (stringValue.isNotEmpty) {
        return stringValue;
      }
    }
    return null;
  }

  static DateTime? _parseDate(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }

    final formats = [
      DateFormat('yyyy-MM-dd'),
      DateFormat('yyyy-MM-ddTHH:mm:ss'),
      DateFormat('yyyy-MM-dd HH:mm:ss'),
    ];

    for (final format in formats) {
      try {
        return format.parse(value, true).toLocal();
      } catch (_) {
        continue;
      }
    }

    return null;
  }
}

enum _JournalRecordType { entry, transfer }

extension on _JournalRecordType {
  String get label => this == _JournalRecordType.entry ? 'Journal Entry' : 'Transfer';
}
