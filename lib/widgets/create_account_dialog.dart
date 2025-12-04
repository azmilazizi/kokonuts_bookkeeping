import 'package:flutter/material.dart';

import '../app/app_state.dart';
import '../app/app_state_scope.dart';
import '../services/accounts_service.dart';
import 'form_error_banner.dart';
import 'searchable_dropdown_form_field.dart';

class CreateAccountDialog extends StatefulWidget {
  const CreateAccountDialog({super.key, this.accountsService});

  final AccountsService? accountsService;

  @override
  State<CreateAccountDialog> createState() => _CreateAccountDialogState();
}

class _CreateAccountDialogState extends State<CreateAccountDialog> {
  late final AccountsService _accountsService;

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();

  List<AccountType> _accountTypes = const [];
  List<AccountDetailType> _detailTypes = const [];
  List<Account> _parentAccounts = const [];

  String? _selectedAccountTypeId;
  String? _selectedDetailTypeId;
  Account? _selectedParentAccount;
  String? _detailNote;

  bool _isLoading = true;
  bool _isLoadingDetails = false;
  bool _isSubmitting = false;
  String? _error;

  Map<String, String>? _headers;

  @override
  void initState() {
    super.initState();
    _accountsService = widget.accountsService ?? AccountsService();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadReferenceData();
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadReferenceData() async {
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
    _headers = headers;

    try {
      final accountTypesFuture = _accountsService.fetchAccountTypes(headers: headers);
      final parentAccountsFuture = _accountsService.fetchAccounts(
        page: 1,
        perPage: 200,
        headers: headers,
        includeBalances: false,
      );

      final accountTypes = await accountTypesFuture;
      final parentAccounts = await parentAccountsFuture;

      String? initialAccountTypeId = _selectedAccountTypeId;
      if (initialAccountTypeId == null && accountTypes.isNotEmpty) {
        initialAccountTypeId = accountTypes.first.id;
      }

      setState(() {
        _accountTypes = accountTypes;
        _parentAccounts = parentAccounts.accounts;
        _selectedAccountTypeId = initialAccountTypeId;
        _selectedParentAccount = _selectedParentAccount == null
            ? null
            : _parentAccounts.firstWhere(
                (account) => account.id == _selectedParentAccount!.id,
                orElse: () => _selectedParentAccount!,
              );
      });

      if (initialAccountTypeId != null) {
        await _loadDetailTypes(initialAccountTypeId, headers);
      }

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _loadDetailTypes(String accountTypeId, Map<String, String> headers) async {
    setState(() {
      _isLoadingDetails = true;
      _detailTypes = const [];
      _selectedDetailTypeId = null;
      _detailNote = null;
      _error = null;
    });

    try {
      final detailTypes = await _accountsService.fetchAccountDetailTypes(
        accountTypeId: accountTypeId,
        headers: headers,
      );

      String? initialDetailTypeId = _selectedDetailTypeId;
      if (initialDetailTypeId == null && detailTypes.isNotEmpty) {
        initialDetailTypeId = detailTypes.first.id;
      }

      setState(() {
        _detailTypes = detailTypes;
        _selectedDetailTypeId = initialDetailTypeId;
        _detailNote = _resolveDetailNote(initialDetailTypeId);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingDetails = false;
        });
      }
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
    return {
      'Accept': 'application/json',
      'authtoken': authtokenHeader,
      'Authorization': normalizedAuth,
    };
  }

  String? _resolveDetailNote(String? detailTypeId) {
    if (detailTypeId == null) return null;
    for (final detail in _detailTypes) {
      if (detail.id == detailTypeId) {
        return detail.note?.trim();
      }
    }
    return null;
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final headers = _headers;
    if (headers == null) {
      setState(() {
        _error = 'Authentication headers are missing.';
      });
      return;
    }

    final accountTypeId = _selectedAccountTypeId;
    final detailTypeId = _selectedDetailTypeId;
    if (accountTypeId == null || detailTypeId == null) {
      setState(() {
        _error = 'Account type and detail type are required.';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      final created = await _accountsService.createAccount(
        name: _nameController.text.trim(),
        accountTypeId: accountTypeId,
        accountDetailTypeId: detailTypeId,
        parentAccountId: _selectedParentAccount?.id,
        headers: headers,
      );

      if (mounted) {
        Navigator.of(context).pop(created);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create Account'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_error != null) ...[
                  FormErrorBanner(message: _error!),
                  const SizedBox(height: 12),
                ],
                if (_isLoading)
                  const Center(child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(),
                  ))
                else
                  ...[
                    _buildAccountTypeField(),
                    const SizedBox(height: 12),
                    _buildDetailTypeField(),
                    const SizedBox(height: 8),
                    _buildDetailNoteSection(),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Account Name',
                        hintText: 'Inventory Assets - Toppings - Ice Cream',
                      ),
                      enabled: !_isSubmitting,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Account name is required';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    _buildParentAccountField(),
                  ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          onPressed:
              _isSubmitting || _isLoading || _isLoadingDetails ? null : _handleSubmit,
          icon: const Icon(Icons.check),
          label: _isSubmitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Create Account'),
        ),
      ],
    );
  }

  Widget _buildAccountTypeField() {
    return DropdownButtonFormField<String>(
      value: _selectedAccountTypeId,
      decoration: const InputDecoration(labelText: 'Account Type'),
      items: _accountTypes
          .map(
            (type) => DropdownMenuItem(
              value: type.id,
              child: Text(type.name),
            ),
          )
          .toList(),
      onChanged: _isSubmitting
          ? null
          : (value) async {
              if (value == null || value == _selectedAccountTypeId) return;
              setState(() {
                _selectedAccountTypeId = value;
              });
              final headers = _headers;
              if (headers != null) {
                await _loadDetailTypes(value, headers);
              }
            },
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Account type is required';
        }
        return null;
      },
    );
  }

  Widget _buildDetailTypeField() {
    return DropdownButtonFormField<String>(
      value: _selectedDetailTypeId,
      decoration: InputDecoration(
        labelText: 'Account Detail Type',
        suffixIcon: _isLoadingDetails
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : null,
      ),
      items: _detailTypes
          .map(
            (type) => DropdownMenuItem(
              value: type.id,
              child: Text(type.name),
            ),
          )
          .toList(),
      onChanged: _isSubmitting
          ? null
          : (value) {
              setState(() {
                _selectedDetailTypeId = value;
                _detailNote = _resolveDetailNote(value);
              });
            },
      validator: (value) {
        if (_isLoadingDetails) return null;
        if (value == null || value.isEmpty) {
          return 'Account detail type is required';
        }
        return null;
      },
    );
  }

  Widget _buildDetailNoteSection() {
    final note = _detailNote;
    if (note == null || note.isEmpty) {
      return Text(
        'No note available for this detail type.',
        style: Theme.of(context).textTheme.bodySmall,
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(note),
    );
  }

  Widget _buildParentAccountField() {
    return SearchableDropdownFormField<Account>(
      items: _parentAccounts,
      itemToString: (account) => account.name,
      initialValue: _selectedParentAccount,
      hintText: 'Select a parent account (optional)',
      dialogTitle: 'Parent Account',
      enabled: !_isSubmitting,
      onChanged: (value) {
        setState(() {
          _selectedParentAccount = value;
        });
      },
      decoration: const InputDecoration(labelText: 'Parent Account'),
      validator: (_) => null,
    );
  }
}
