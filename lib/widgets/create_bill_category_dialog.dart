import 'package:flutter/material.dart';

import '../services/accounts_service.dart';
import '../services/bill_category_service.dart';
import 'searchable_dropdown_form_field.dart';

Future<BillCategory?> showCreateBillCategoryDialog({
  required BuildContext context,
  required Map<String, String> headers,
  required List<Account> accounts,
}) {
  return showDialog<BillCategory>(
    context: context,
    builder: (context) => _CreateBillCategoryDialog(
      headers: headers,
      accounts: accounts,
    ),
  );
}

class _CreateBillCategoryDialog extends StatefulWidget {
  const _CreateBillCategoryDialog({
    required this.headers,
    required this.accounts,
  });

  final Map<String, String> headers;
  final List<Account> accounts;

  @override
  State<_CreateBillCategoryDialog> createState() =>
      _CreateBillCategoryDialogState();
}

class _CreateBillCategoryDialogState
    extends State<_CreateBillCategoryDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _categoryService = BillCategoryService();

  String? _selectedDebitAccountId;
  String? _selectedCreditAccountId;
  bool _isSubmitting = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  String _accountLabel(String id) {
    return widget.accounts
        .firstWhere(
          (a) => a.id == id,
          orElse: () => Account(
            id: id,
            name: 'Unknown account',
            parentAccountId: '',
            typeName: '',
            detailTypeName: '',
            balance: '',
            primaryBalance: '',
            isActive: false,
          ),
        )
        .name;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      final debitId = int.tryParse(_selectedDebitAccountId ?? '');
      final creditId = int.tryParse(_selectedCreditAccountId ?? '');

      final created = await _categoryService.createCategory(
        headers: widget.headers,
        name: _nameController.text.trim(),
        debitAccount: debitId,
        creditAccount: creditId,
      );

      if (mounted) {
        Navigator.of(context).pop(created);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Add Bill Category'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Category name'),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Category name is required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              SearchableDropdownFormField<String>(
                decoration: const InputDecoration(
                  labelText: 'Default debit account (optional)',
                ),
                initialValue: _selectedDebitAccountId,
                items: widget.accounts.map((a) => a.id).toList(),
                itemToString: _accountLabel,
                hintText: 'Select an account',
                dialogTitle: 'Select debit account',
                onChanged: (value) =>
                    setState(() => _selectedDebitAccountId = value),
              ),
              const SizedBox(height: 12),
              SearchableDropdownFormField<String>(
                decoration: const InputDecoration(
                  labelText: 'Default credit account (optional)',
                ),
                initialValue: _selectedCreditAccountId,
                items: widget.accounts.map((a) => a.id).toList(),
                itemToString: _accountLabel,
                hintText: 'Select an account',
                dialogTitle: 'Select credit account',
                onChanged: (value) =>
                    setState(() => _selectedCreditAccountId = value),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isSubmitting ? null : _submit,
          child: _isSubmitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}
