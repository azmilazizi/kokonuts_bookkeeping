import 'package:flutter/material.dart';

class TableFilterBar extends StatelessWidget {
  const TableFilterBar({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.hintText,
    this.labelText = 'Filter',
    this.isFiltering = false,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String hintText;
  final String labelText;
  final bool isFiltering;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final background = theme.colorScheme.surfaceVariant.withOpacity(0.6);

    return Container(
      color: background,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: labelText,
          hintText: hintText,
          prefixIcon: const Icon(Icons.search),
          suffixIcon: isFiltering
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    if (controller.text.isEmpty) {
                      return;
                    }
                    controller.clear();
                    onChanged('');
                  },
                )
              : null,
          border: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
          isDense: true,
        ),
      ),
    );
  }
}
