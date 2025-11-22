import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'attachment_picker.dart';

class CreateBillDialog extends StatefulWidget {
  const CreateBillDialog({super.key});

  @override
  State<CreateBillDialog> createState() => _CreateBillDialogState();
}

class _CreateBillDialogState extends State<CreateBillDialog>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(length: 2, vsync: this);
  final _nameController = TextEditingController();
  final _referenceController = TextEditingController();
  final _debitAmountController = TextEditingController();
  final _creditAmountController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _quantityController = TextEditingController(text: '1');
  final _priceController = TextEditingController(text: '0.00');

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
    _tabController.dispose();
    _nameController.dispose();
    _referenceController.dispose();
    _debitAmountController.dispose();
    _creditAmountController.dispose();
    _descriptionController.dispose();
    _quantityController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  double get _itemTotal {
    final qty = double.tryParse(_quantityController.text) ?? 0;
    final price = double.tryParse(_priceController.text) ?? 0;
    return qty * price;
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
              _buildEndpointPill(theme),
              const SizedBox(height: 16),
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
                  _buildReferenceField(),
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
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TabBar(
                    controller: _tabController,
                    labelColor: theme.colorScheme.onSurface,
                    tabs: const [
                      Tab(text: 'Expenses'),
                      Tab(text: 'Items'),
                    ],
                  ),
                  SizedBox(
                    height: 260,
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildExpensesTab(),
                        _buildItemsTab(),
                      ],
                    ),
                  ),
                ],
              ),
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
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Bill form saved locally. Submit to POST /accounting/api/v1/bills'),
              ),
            );
            Navigator.of(context).pop();
          },
          child: const Text('Save'),
        ),
      ],
    );
  }

  Widget _buildEndpointPill(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceVariant,
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 10,
        children: [
          Chip(label: Text('POST')),
          SelectableText('https://crm.kokonuts.my/accounting/api/v1/bills'),
        ],
      ),
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

  Widget _buildReferenceField() {
    return SizedBox(
      width: 300,
      child: TextFormField(
        controller: _referenceController,
        decoration: const InputDecoration(labelText: 'Reference #'),
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
            decoration: const InputDecoration(labelText: 'Amount'),
          ),
        ),
      ],
    );
  }

  Widget _buildItemsTab() {
    final totalLabel = _itemTotal.toStringAsFixed(2);
    return Padding(
      padding: const EdgeInsets.only(top: 12, right: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            controller: _descriptionController,
            decoration: const InputDecoration(labelText: 'Description'),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _quantityController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Quantity'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _priceController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Price'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'Total'),
                  child: Text(totalLabel),
                ),
              ),
            ],
          ),
        ],
      ),
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
