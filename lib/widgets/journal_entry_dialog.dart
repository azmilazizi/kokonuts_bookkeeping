import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'attachment_picker.dart';
import 'currency_input_formatter.dart';

class JournalEntryDialog extends StatefulWidget {
  const JournalEntryDialog({super.key});

  @override
  State<JournalEntryDialog> createState() => _JournalEntryDialogState();
}

class _JournalEntryDialogState extends State<JournalEntryDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController(
    text: CurrencyInputFormatter.normalizeExistingValue(null),
  );
  final _descriptionController = TextEditingController();
  final _dateController = TextEditingController();

  DateTime _journalDate = DateTime.now();
  String? _transactionType;
  List<PlatformFile> _attachments = const [];
  final List<_JournalEntry> _entries = [
    _JournalEntry(
      journalDate: DateTime.now(),
      transactionType: 'Debit',
      amount: 1250.35,
      description: 'Office supplies',
    ),
    _JournalEntry(
      journalDate: DateTime.now().subtract(const Duration(days: 2)),
      transactionType: 'Credit',
      amount: 980.00,
      description: 'Client payment',
    ),
  ];

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    _dateController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _updateDateText();
  }

  Future<void> _pickAttachments() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
      withReadStream: true,
      type: FileType.custom,
      allowedExtensions: allowedAttachmentExtensions.toList(),
    );

    if (result == null || result.files.isEmpty) {
      return;
    }

    final validFiles = result.files
        .where(
          (file) => isAllowedAttachmentExtension(
            attachmentExtension(file.name),
          ),
        )
        .toList();

    if (validFiles.isEmpty) {
      return;
    }

    setState(() {
      _attachments = [..._attachments, ...validFiles];
    });
  }

  void _onFilesSelected(List<PlatformFile> files) {
    setState(() => _attachments = files);
  }

  void _removeAttachment(PlatformFile file) {
    setState(() {
      _attachments = List.of(_attachments)..remove(file);
    });
  }

  Future<void> _pickDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _journalDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );

    if (selected != null) {
      setState(() {
        _journalDate = selected;
        _updateDateText();
      });
    }
  }

  String get _formattedDate => DateFormat('yyyy-MM-dd').format(_journalDate);

  void _updateDateText() {
    _dateController.text = _formattedDate;
  }

  void _fillFormFromEntry(_JournalEntry entry) {
    setState(() {
      _journalDate = entry.journalDate;
      _updateDateText();
      _transactionType = entry.transactionType;
      _amountController.text =
          CurrencyInputFormatter.normalizeExistingValue(entry.amount.toString());
      _descriptionController.text = entry.description;
      _attachments = const [];
    });
  }

  void _showEntriesTable() {
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            void removeEntry(_JournalEntry entry) {
              setState(() => _entries.remove(entry));
              setLocalState(() {});
            }

            return AlertDialog(
              title: const Text('Journal Entries'),
              content: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Date')),
                    DataColumn(label: Text('Type')),
                    DataColumn(label: Text('Amount')),
                    DataColumn(label: Text('Description')),
                    DataColumn(label: Text('Actions')),
                  ],
                  rows: _entries
                      .map(
                        (entry) => DataRow(
                          cells: [
                            DataCell(Text(DateFormat('yyyy-MM-dd').format(
                              entry.journalDate,
                            ))),
                            DataCell(Text(entry.transactionType)),
                            DataCell(Text(entry.amount.toStringAsFixed(2))),
                            DataCell(Text(entry.description)),
                            DataCell(
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit),
                                    tooltip: 'Edit entry',
                                    onPressed: () {
                                      _fillFormFromEntry(entry);
                                      Navigator.of(context).pop();
                                    },
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline),
                                    tooltip: 'Delete entry',
                                    onPressed: () => removeEntry(entry),
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
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _submit() {
    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid) {
      return;
    }

    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final dialogWidth = (MediaQuery.of(context).size.width * 0.92).clamp(
      420.0,
      840.0,
    );

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 12, 0),
      title: Row(
        children: [
          const Expanded(
            child: Text(
              'Journal Entry',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          TextButton.icon(
            onPressed: _showEntriesTable,
            icon: const Icon(Icons.table_rows),
            label: const Text('All Entries'),
            style: TextButton.styleFrom(minimumSize: const Size(0, 36)),
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
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(right: 12, bottom: 12),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AttachmentPicker(
                  label: 'Attachments',
                  description: 'Upload receipts, statements, or supporting files.',
                  files: _attachments,
                  onPick: _pickAttachments,
                  onFilesSelected: _onFilesSelected,
                  onFileRemoved: _removeAttachment,
                ),
                const SizedBox(height: 20),
                TextFormField(
                  readOnly: true,
                  controller: _dateController,
                  decoration: const InputDecoration(
                    labelText: 'Journal Date',
                    prefixIcon: Icon(Icons.event),
                  ),
                  onTap: _pickDate,
                ),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth >= 600;
                    final fields = [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _transactionType,
                          items: const [
                            DropdownMenuItem(value: 'Debit', child: Text('Debit')),
                            DropdownMenuItem(value: 'Credit', child: Text('Credit')),
                          ],
                          decoration: const InputDecoration(
                            labelText: 'Transaction Type',
                          ),
                          onChanged: (value) => setState(() => _transactionType = value),
                          validator: (value) =>
                              value == null ? 'Please select a transaction type' : null,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextFormField(
                          controller: _amountController,
                          keyboardType: TextInputType.number,
                          inputFormatters: const [CurrencyInputFormatter()],
                          decoration: const InputDecoration(
                            labelText: 'Amount',
                            prefixIcon: Icon(Icons.payments_outlined),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Amount is required';
                            }
                            return null;
                          },
                        ),
                      ),
                    ];

                    if (isWide) {
                      return Row(
                        children: fields,
                      );
                    }

                    return Column(
                      children: [
                        fields[0],
                        const SizedBox(height: 16),
                        fields[2],
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    alignLabelWithHint: true,
                  ),
                  maxLines: 4,
                  minLines: 3,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _submit,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _JournalEntry {
  _JournalEntry({
    required this.journalDate,
    required this.transactionType,
    required this.amount,
    required this.description,
  });

  final DateTime journalDate;
  final String transactionType;
  final double amount;
  final String description;
}
