import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

enum QuickPeriod { thisMonth, lastMonth, thisQuarter, thisYear, custom }

String quickPeriodLabel(QuickPeriod p) {
  switch (p) {
    case QuickPeriod.thisMonth:
      return 'This Month';
    case QuickPeriod.lastMonth:
      return 'Last Month';
    case QuickPeriod.thisQuarter:
      return 'This Quarter';
    case QuickPeriod.thisYear:
      return 'This Year';
    case QuickPeriod.custom:
      return 'Custom';
  }
}

DateTimeRange quickPeriodRange(QuickPeriod period) {
  final now = DateTime.now();
  switch (period) {
    case QuickPeriod.thisMonth:
      return DateTimeRange(
        start: DateTime(now.year, now.month, 1),
        end: DateTime(now.year, now.month + 1, 0),
      );
    case QuickPeriod.lastMonth:
      return DateTimeRange(
        start: DateTime(now.year, now.month - 1, 1),
        end: DateTime(now.year, now.month, 0),
      );
    case QuickPeriod.thisQuarter:
      final q = (now.month - 1) ~/ 3;
      return DateTimeRange(
        start: DateTime(now.year, q * 3 + 1, 1),
        end: DateTime(now.year, q * 3 + 4, 0),
      );
    case QuickPeriod.thisYear:
      return DateTimeRange(
        start: DateTime(now.year, 1, 1),
        end: DateTime(now.year, 12, 31),
      );
    case QuickPeriod.custom:
      return DateTimeRange(
        start: DateTime(now.year, now.month, 1),
        end: DateTime(now.year, now.month + 1, 0),
      );
  }
}

/// A self-contained preset date picker bar with optional accounting method
/// toggle. Manages period selection internally; reports changes via callbacks.
class PresetDatePickerBar extends StatefulWidget {
  const PresetDatePickerBar({
    super.key,
    this.initialPeriod = QuickPeriod.thisMonth,
    this.initialStartDate,
    this.initialEndDate,
    this.showMethodToggle = false,
    this.initialMethod = 'payment',
    required this.onDateRangeChanged,
    this.onMethodChanged,
  });

  final QuickPeriod initialPeriod;
  final DateTime? initialStartDate;
  final DateTime? initialEndDate;

  /// Show the Cash / Accrual pill toggle above the period chips.
  final bool showMethodToggle;

  /// 'payment' (cash) or 'issued' (accrual).
  final String initialMethod;

  final void Function(DateTime start, DateTime end) onDateRangeChanged;
  final ValueChanged<String>? onMethodChanged;

  @override
  State<PresetDatePickerBar> createState() => _PresetDatePickerBarState();
}

class _PresetDatePickerBarState extends State<PresetDatePickerBar> {
  late QuickPeriod _period;
  late DateTime _start;
  late DateTime _end;
  late String _method;

  @override
  void initState() {
    super.initState();
    _method = widget.initialMethod;
    _period = widget.initialPeriod;

    if (widget.initialStartDate != null && widget.initialEndDate != null) {
      _start = widget.initialStartDate!;
      _end = widget.initialEndDate!;
    } else {
      final range = quickPeriodRange(_period);
      _start = range.start;
      _end = range.end;
    }
  }

  void _selectPreset(QuickPeriod period) {
    if (period == QuickPeriod.custom) {
      _openCustomPicker();
      return;
    }
    final range = quickPeriodRange(period);
    setState(() {
      _period = period;
      _start = range.start;
      _end = range.end;
    });
    widget.onDateRangeChanged(_start, _end);
  }

  Future<void> _openCustomPicker() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDateRange: DateTimeRange(start: _start, end: _end),
    );
    if (picked != null) {
      setState(() {
        _period = QuickPeriod.custom;
        _start = picked.start;
        _end = picked.end;
      });
      widget.onDateRangeChanged(_start, _end);
    }
  }

  String get _rangeLabel {
    final df = DateFormat('MMM d');
    final dfYear = DateFormat('MMM d, yyyy');
    final sameYear = _start.year == _end.year;
    return sameYear
        ? '${df.format(_start)} – ${dfYear.format(_end)}'
        : '${dfYear.format(_start)} – ${dfYear.format(_end)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final presets = QuickPeriod.values
        .where((p) => p != QuickPeriod.custom || _period == QuickPeriod.custom)
        .toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (widget.showMethodToggle) ...[
                _MethodToggle(
                  value: _method,
                  onChanged: (v) {
                    setState(() => _method = v);
                    widget.onMethodChanged?.call(v);
                  },
                ),
                const Spacer(),
              ] else
                const Spacer(),
              TextButton.icon(
                style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  foregroundColor: theme.colorScheme.onSurfaceVariant,
                ),
                icon: const Icon(Icons.calendar_today, size: 14),
                label: Text(_rangeLabel, style: theme.textTheme.bodySmall),
                onPressed: _openCustomPicker,
              ),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: presets
                  .map((p) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _PeriodChip(
                          label: quickPeriodLabel(p),
                          selected: _period == p,
                          onTap: () => _selectPreset(p),
                        ),
                      ))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _MethodToggle extends StatelessWidget {
  const _MethodToggle({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _toggle('Cash', 'payment', theme),
          _toggle('Accrual', 'issued', theme),
        ],
      ),
    );
  }

  Widget _toggle(String label, String v, ThemeData theme) {
    final isSelected = value == v;
    return GestureDetector(
      onTap: () => onChanged(v),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? theme.colorScheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: isSelected
                ? theme.colorScheme.onPrimary
                : theme.colorScheme.onSurfaceVariant,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

class _PeriodChip extends StatelessWidget {
  const _PeriodChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
          border: selected
              ? Border.all(color: theme.colorScheme.primary, width: 1.5)
              : null,
        ),
        child: Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
