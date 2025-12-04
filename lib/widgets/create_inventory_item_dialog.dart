import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../services/auth_http_client.dart';
import '../services/inventory_items_service.dart';

Future<InventoryItem?> showCreateInventoryItemDialog({
  required BuildContext context,
  required Map<String, String> headers,
}) {
  return showDialog<InventoryItem>(
    context: context,
    builder: (context) => _CreateInventoryItemDialog(headers: headers),
  );
}

class _CreateInventoryItemDialog extends StatefulWidget {
  const _CreateInventoryItemDialog({required this.headers});

  final Map<String, String> headers;

  @override
  State<_CreateInventoryItemDialog> createState() => _CreateInventoryItemDialogState();
}

class _CreateInventoryItemDialogState extends State<_CreateInventoryItemDialog> {
  final _formKey = GlobalKey<FormState>();
  final _itemCodeController = TextEditingController();
  final _itemNameController = TextEditingController();

  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _error;

  List<_DropdownOption> _groups = const [];
  List<_DropdownOption> _units = const [];
  List<_DropdownOption> _inventoryAccounts = const [];
  List<_DropdownOption> _incomeAccounts = const [];
  List<_DropdownOption> _expenseAccounts = const [];

  String? _selectedGroupId;
  String? _selectedUnitId;
  String? _inventoryAssetAccountId;
  String? _incomeAccountId;
  String? _expenseAccountId;

  @override
  void initState() {
    super.initState();
    _loadReferenceData();
  }

  @override
  void dispose() {
    _itemCodeController.dispose();
    _itemNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create Item'),
      content: SizedBox(
        width: 520,
        child: _isLoading
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: Center(child: CircularProgressIndicator()),
              )
            : _buildForm(),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isSubmitting || _isLoading ? null : _submit,
          child: _isSubmitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Create'),
        ),
      ],
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _itemCodeController,
              decoration: const InputDecoration(
                labelText: 'Item Code',
                hintText: '2L-CHOC-SAUCE',
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Item Code is required';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _itemNameController,
              decoration: const InputDecoration(
                labelText: 'Item Name',
                hintText: '2L Chocolate Sauce',
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Item Name is required';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildDropdown(
                    label: 'Item Group',
                    value: _selectedGroupId,
                    options: _groups,
                    onChanged: (value) => setState(() => _selectedGroupId = value),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildDropdown(
                    label: 'Unit',
                    value: _selectedUnitId,
                    options: _units,
                    onChanged: (value) => setState(() => _selectedUnitId = value),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildDropdown(
              label: 'Inventory Assets Account',
              value: _inventoryAssetAccountId,
              options: _inventoryAccounts,
              onChanged: (value) => setState(() => _inventoryAssetAccountId = value),
            ),
            const SizedBox(height: 12),
            _buildDropdown(
              label: 'Income Account',
              value: _incomeAccountId,
              options: _incomeAccounts,
              onChanged: (value) => setState(() => _incomeAccountId = value),
            ),
            const SizedBox(height: 12),
            _buildDropdown(
              label: 'Expense Account',
              value: _expenseAccountId,
              options: _expenseAccounts,
              onChanged: (value) => setState(() => _expenseAccountId = value),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDropdown({
    required String label,
    required String? value,
    required List<_DropdownOption> options,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      value: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: options
          .map(
            (option) => DropdownMenuItem<String>(
              value: option.id,
              child: Text(option.label),
            ),
          )
          .toList(),
      onChanged: _isSubmitting ? null : onChanged,
      validator: (selected) {
        if (selected == null || selected.isEmpty) {
          return '$label is required';
        }
        return null;
      },
    );
  }

  Future<void> _loadReferenceData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final client = createAuthAwareClient();
      final results = await Future.wait([
        _fetchOptions(
          client,
          Uri.parse('https://crm.kokonuts.my/warehouse/api/v1/item_groups'),
          idKeys: const ['id', 'group_id', 'groupId'],
          labelKeys: const ['label', 'name', 'group_name', 'groupName'],
          labelTransformer: _trimGroupLabel,
        ),
        _fetchOptions(
          client,
          Uri.parse('https://crm.kokonuts.my/warehouse/api/v1/units'),
          idKeys: const ['id'],
          labelKeys: const ['label'],
        ),
        _fetchAccounts(
          client,
          Uri.parse(
            'https://crm.kokonuts.my/accounting/api/v1/accounts?account_type_name=Current Assets',
          ),
        ),
        _fetchAccounts(
          client,
          Uri.parse(
            'https://crm.kokonuts.my/accounting/api/v1/accounts?account_type_name=Income',
          ),
        ),
        _fetchAccounts(
          client,
          Uri.parse(
            'https://crm.kokonuts.my/accounting/api/v1/accounts?account_type_name=Cost of sales',
          ),
        ),
      ]);

      final groups = results[0] as List<_DropdownOption>;
      final units = results[1] as List<_DropdownOption>;
      final inventoryAccounts = results[2] as List<_DropdownOption>;
      final incomeAccounts = results[3] as List<_DropdownOption>;
      final expenseAccounts = results[4] as List<_DropdownOption>;

      setState(() {
        _groups = groups;
        _units = units;
        _selectedGroupId = groups.isNotEmpty ? groups.first.id : null;
        _selectedUnitId = units.isNotEmpty ? units.first.id : null;
        _inventoryAccounts = inventoryAccounts;
        _incomeAccounts = incomeAccounts;
        _expenseAccounts = expenseAccounts;
        _inventoryAssetAccountId =
            inventoryAccounts.isNotEmpty ? inventoryAccounts.first.id : null;
        _incomeAccountId = incomeAccounts.isNotEmpty ? incomeAccounts.first.id : null;
        _expenseAccountId = expenseAccounts.isNotEmpty ? expenseAccounts.first.id : null;
        _isLoading = false;
      });
    } catch (error) {
      setState(() {
        _error = 'Failed to load reference data: $error';
        _isLoading = false;
      });
    }
  }

  Future<List<_DropdownOption>> _fetchOptions(
    http.Client client,
    Uri uri, {
    required List<String> idKeys,
    required List<String> labelKeys,
    String Function(String label)? labelTransformer,
  }) async {
    http.Response response;
    try {
      response = await client.get(uri, headers: widget.headers);
    } catch (error) {
      throw 'Failed to reach server: $error';
    }

    if (response.statusCode != 200) {
      throw 'Request failed with status ${response.statusCode}: ${response.body}';
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (error) {
      throw 'Unable to parse response: $error';
    }

    final results = <_DropdownOption>[];
    void collect(dynamic source) {
      if (source is Map<String, dynamic>) {
        final id = _firstMatchingString(source, idKeys);
        final label = _firstMatchingString(source, labelKeys);
        if (id != null && label != null) {
          results.add(
            _DropdownOption(
              id: id,
              label: labelTransformer != null ? labelTransformer(label) : label,
            ),
          );
        }
        for (final value in source.values) {
          collect(value);
        }
      } else if (source is List) {
        for (final entry in source) {
          collect(entry);
        }
      }
    }

    collect(decoded);
    final unique = {for (final option in results) option.id: option};
    final sorted = unique.values.toList()
      ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    return sorted;
  }

  Future<List<_DropdownOption>> _fetchAccounts(http.Client client, Uri uri) {
    return _fetchOptions(
      client,
      uri,
      idKeys: const ['id'],
      labelKeys: const ['name', 'label'],
    );
  }

  String _trimGroupLabel(String label) {
    final underscoreIndex = label.indexOf('_');
    if (underscoreIndex == -1) return label;
    return label.substring(0, underscoreIndex);
  }

  String? _firstMatchingString(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
      if (value is num) {
        return value.toString();
      }
    }
    return null;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    final itemCode = _itemCodeController.text.trim();
    final itemName = _itemNameController.text.trim();

    final createBody = jsonEncode({
      'commodity_code': itemCode,
      'description': itemName,
      'sku_code': itemCode,
      'sku_name': itemName,
      'group_id': _selectedGroupId,
      'unit_id': _selectedUnitId,
      'rate': 0,
      'tax': 0,
    });

    http.Response response;
    final client = createAuthAwareClient();
    try {
      response = await client.post(
        Uri.parse('https://crm.kokonuts.my/warehouse/api/v1/items'),
        headers: {
          ...widget.headers,
          'Content-Type': 'application/json',
        },
        body: createBody,
      );
    } catch (error) {
      _setError('Failed to reach server: $error');
      return;
    }

    if (response.statusCode != 200 && response.statusCode != 201) {
      _setError('Request failed with status ${response.statusCode}: ${response.body}');
      return;
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      decoded = null;
    }

    final itemId = _extractItemId(decoded);
    if (itemId == null) {
      _setError('Unable to determine created item ID.');
      return;
    }

    final mappingBody = jsonEncode({
      'item_id': itemId,
      'inventory_asset_account': _inventoryAssetAccountId,
      'income_account': _incomeAccountId,
      'expense_account': _expenseAccountId,
    });

    try {
      response = await client.post(
        Uri.parse('https://crm.kokonuts.my/warehouse/api/v1/item_account_mapping'),
        headers: {
          ...widget.headers,
          'Content-Type': 'application/json',
        },
        body: mappingBody,
      );
    } catch (error) {
      _setError('Failed to reach server: $error');
      return;
    }

    if (response.statusCode != 200 && response.statusCode != 201) {
      _setError('Request failed with status ${response.statusCode}: ${response.body}');
      return;
    }

    if (mounted) {
      Navigator.of(context).pop(
        InventoryItem(
          id: itemId,
          name: itemName,
          skuCode: itemCode,
          skuName: itemName,
        ),
      );
    }
  }

  String? _extractItemId(dynamic decoded) {
    if (decoded == null) return null;

    String? extract(dynamic source) {
      if (source is Map<String, dynamic>) {
        final id = _firstMatchingString(
          source,
          const ['item_id', 'id', 'uid'],
        );
        if (id != null) return id;
        for (final value in source.values) {
          final found = extract(value);
          if (found != null) return found;
        }
      } else if (source is List) {
        for (final value in source) {
          final found = extract(value);
          if (found != null) return found;
        }
      }
      return null;
    }

    return extract(decoded);
  }

  void _setError(String message) {
    if (!mounted) return;
    setState(() {
      _error = message;
      _isSubmitting = false;
    });
  }
}

class _DropdownOption {
  const _DropdownOption({required this.id, required this.label});

  final String id;
  final String label;
}
