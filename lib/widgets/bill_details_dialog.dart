import 'package:flutter/material.dart';

import '../services/bills_service.dart';

class BillDetailsDialog extends StatelessWidget {
  const BillDetailsDialog({super.key, required this.bill, required this.vendorName});

  final Bill bill;
  final String vendorName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DialogHeader(onClose: () => Navigator.of(context).pop()),
              const SizedBox(height: 12),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _DetailField(label: 'Vendor', value: vendorName.isEmpty ? '—' : vendorName),
                      const SizedBox(height: 12),
                      _DetailField(label: 'Bill ID', value: bill.id.isEmpty ? '—' : bill.id),
                      const SizedBox(height: 12),
                      _DetailField(label: 'Bill date', value: bill.formattedDate),
                      const SizedBox(height: 12),
                      _DetailField(label: 'Due date', value: bill.formattedDueDate),
                      const SizedBox(height: 20),
                      const Divider(thickness: 1.2),
                      const SizedBox(height: 20),
                      _DetailField(
                        label: 'Status',
                        value: bill.status.label,
                        valueStyle: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 12),
                      _DetailField(
                        label: 'Total amount',
                        value: bill.totalLabel,
                        valueStyle: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DialogHeader extends StatelessWidget {
  const _DialogHeader({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            'Bill Details',
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        IconButton(
          tooltip: 'Close',
          onPressed: onClose,
          icon: const Icon(Icons.close),
        ),
      ],
    );
  }
}

class _DetailField extends StatelessWidget {
  const _DetailField({
    required this.label,
    required this.value,
    this.valueStyle,
  });

  final String label;
  final String value;
  final TextStyle? valueStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resolvedValue = value.trim().isEmpty ? '—' : value.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text(resolvedValue, style: valueStyle ?? theme.textTheme.bodyMedium),
      ],
    );
  }
}
