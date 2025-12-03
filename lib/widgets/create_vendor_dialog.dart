import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../services/auth_http_client.dart';
import '../services/vendors_service.dart';

Future<VendorSummary?> showCreateVendorDialog({
  required BuildContext context,
  required Map<String, String> headers,
}) {
  return showDialog<VendorSummary>(
    context: context,
    builder: (context) => _CreateVendorDialog(headers: headers),
  );
}

class _CreateVendorDialog extends StatefulWidget {
  const _CreateVendorDialog({required this.headers});

  final Map<String, String> headers;

  @override
  State<_CreateVendorDialog> createState() => _CreateVendorDialogState();
}

class _CreateVendorDialogState extends State<_CreateVendorDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _codeController = TextEditingController();
  bool _isSubmitting = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create vendor'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Vendor name'),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Vendor name is required';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _codeController,
              decoration: const InputDecoration(labelText: 'Vendor code'),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Vendor code is required';
                }
                return null;
              },
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
              : const Text('Create'),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    final name = _nameController.text.trim();
    final code = _codeController.text.trim();
    final body = jsonEncode({
      'company': name,
      'vendor_code': code,
    });

    http.Response response;
    final client = createAuthAwareClient();
    try {
      response = await client.post(
        Uri.parse('https://crm.kokonuts.my/purchase/api/v1/vendors'),
        headers: {
          ...widget.headers,
          'Content-Type': 'application/json',
        },
        body: body,
      );
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = 'Failed to reach server: $error';
          _isSubmitting = false;
        });
      }
      return;
    }

    if (response.statusCode != 200 && response.statusCode != 201) {
      if (mounted) {
        setState(() {
          _error =
              'Request failed with status ${response.statusCode}: ${response.body}';
          _isSubmitting = false;
        });
      }
      return;
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      decoded = null;
    }

    final summaries = <String, VendorSummary>{};
    if (decoded != null) {
      VendorsService().collectVendorsForParsing(decoded, summaries);
    }
    final created = summaries[name] ??
        (summaries.values.isNotEmpty ? summaries.values.first : null);

    if (mounted) {
      Navigator.of(context).pop(
        created ?? VendorSummary(id: '', name: name, code: code),
      );
    }
  }
}
