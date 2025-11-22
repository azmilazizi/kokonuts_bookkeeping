import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'attachment_picker.dart';
import 'currency_input_formatter.dart';

class CreateBillDialog extends StatefulWidget {
  const CreateBillDialog({super.key});

  @override
  State<CreateBillDialog> createState() => _CreateBillDialogState();
}

class _CreateBillDialogState extends State<CreateBillDialog> {
  final _nameController = TextEditingController();
  final _debitAmountController = TextEditingController();
  final _creditAmountController = TextEditingController();

  DateTime _billDate = DateTime.now();
  DateTime _dueDate = DateTime.now();
  String? _selectedVendor;
  String? _selectedDebitAccount;
  String? _selectedCreditAccount;
  List<PlatformFile> _attachments = [];

  final _vendors = const ['Vendor A', 'Vendor B', 'Vendor C'];
  final _accounts = const ['None selected', 'Account 1', 'Account 2'];

  @override
  void dispose() {
    _nameController.dispose();
    _debitAmountController.dispose();
    _creditAmountController.dispose();
    super.dispose();
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
          (file) =>
              isAllowedAttachmentExtension(attachmentExtension(file.name)),
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

  @override
  void initState() {
    super.initState();
    _debitAmountController.text =
        CurrencyInputFormatter.normalizeExistingValue(_debitAmountController.text);
    _creditAmountController.text =
        CurrencyInputFormatter.normalizeExistingValue(_creditAmountController.text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dialogWidth = (MediaQuery.of(context).size.width * 0.95).clamp(420.0, 1040.0);

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 12, 0),
      title: Row(
        children: [
          const Expanded(
            child: Text(
              'Add New Bill',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          IconButton(
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
          )
        ],
      ),
      content: SizedBox(
        width: dialogWidth,
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(right: 12, bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 16,
                runSpacing: 12,
                children: [
                  _buildVendorDropdown(theme),
                  _buildDateField(
                    label: 'Bill date',
                    value: _billDate,
                    onTap: () => _pickDate(isBillDate: true),
                  ),
                  _buildNameField(),
                  _buildDateField(
                    label: 'Due date',
                    value: _dueDate,
                    onTap: () => _pickDate(isBillDate: false),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text('Attachment', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              AttachmentPicker(
                description:
                    'Drag and drop supporting files here, or click to browse for uploads.',
                files: _attachments,
                onPick: _pickAttachments,
                onFilesSelected: _onFilesSelected,
                onFileRemoved: _removeAttachment,
              ),
              const SizedBox(height: 20),
              Text('Expenses', style: theme.textTheme.titleMedium),
              _buildExpensesTab(),
            ],
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: const Text('Save'),
        ),
      ],
    );
  }

  Widget _buildVendorDropdown(ThemeData theme) {
    return SizedBox(
      width: 300,
      child: DropdownButtonFormField<String>(
        decoration: const InputDecoration(labelText: 'Vendor'),
        value: _selectedVendor,
        items: _vendors
            .map((vendor) => DropdownMenuItem<String>(
                  value: vendor,
                  child: Text(vendor),
                ))
            .toList(),
        onChanged: (value) => setState(() => _selectedVendor = value),
      ),
    );
  }

  Widget _buildNameField() {
    return SizedBox(
      width: 300,
      child: TextFormField(
        controller: _nameController,
        decoration: const InputDecoration(labelText: 'Name'),
      ),
    );
  }

  Widget _buildDateField({
    required String label,
    required DateTime value,
    required VoidCallback onTap,
  }) {
    final formatted = DateFormat('dd-MM-yyyy').format(value);
    return SizedBox(
      width: 300,
      child: InkWell(
        onTap: onTap,
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            suffixIcon: const Icon(Icons.calendar_today_outlined),
          ),
          child: Text(formatted),
        ),
      ),
    );
  }

  Widget _buildExpensesTab() {
    return Padding(
      padding: const EdgeInsets.only(top: 12, right: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildAccountRow(
            label: 'Debit account',
            selected: _selectedDebitAccount,
            onChanged: (value) => setState(() => _selectedDebitAccount = value),
            amountController: _debitAmountController,
          ),
          const SizedBox(height: 14),
          _buildAccountRow(
            label: 'Credit account',
            selected: _selectedCreditAccount,
            onChanged: (value) => setState(() => _selectedCreditAccount = value),
            amountController: _creditAmountController,
          ),
        ],
      ),
    );
  }

  Widget _buildAccountRow({
    required String label,
    required String? selected,
    required ValueChanged<String?> onChanged,
    required TextEditingController amountController,
  }) {
    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            decoration: InputDecoration(labelText: label),
            value: selected,
            items: _accounts
                .map((account) => DropdownMenuItem<String>(
                      value: account,
                      child: Text(account),
                    ))
                .toList(),
            onChanged: onChanged,
          ),
        ),
        const SizedBox(width: 16),
        SizedBox(
          width: 160,
          child: TextFormField(
            controller: amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: const [CurrencyInputFormatter()],
            decoration: const InputDecoration(labelText: 'Amount'),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  Future<void> _pickDate({required bool isBillDate}) async {
    final initialDate = isBillDate ? _billDate : _dueDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );

    if (picked != null) {
      setState(() {
        if (isBillDate) {
          _billDate = picked;
        } else {
          _dueDate = picked;
        }
      });
    }
  }
}
