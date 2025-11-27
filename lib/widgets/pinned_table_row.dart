import 'package:flutter/material.dart';

class PinnedTableRow extends StatelessWidget {
  const PinnedTableRow({
    super.key,
    required this.columnFlex,
    required this.cells,
    required this.horizontalController,
    this.pinnedColumnIndex,
    this.overlayDecoration,
  }) : assert(columnFlex.length == cells.length,
            'Column flex and cell count must match');

  final List<int> columnFlex;
  final List<Widget> cells;
  final ScrollController horizontalController;
  final int? pinnedColumnIndex;
  final BoxDecoration? overlayDecoration;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final totalFlex = columnFlex.fold<int>(0, (total, flex) => total + flex);
        final columnWidths = columnFlex
            .map((flex) => width * (flex / totalFlex))
            .toList(growable: false);

        final pinnedIndex = pinnedColumnIndex;
        if (pinnedIndex == null || pinnedIndex < 0 || pinnedIndex >= cells.length) {
          return Row(
            children: [
              for (var i = 0; i < cells.length; i++)
                SizedBox(width: columnWidths[i], child: cells[i]),
            ],
          );
        }

        final pinnedWidth = columnWidths[pinnedIndex];
        final pinnedCell = cells[pinnedIndex];
        final nonPinnedCells = <Widget>[];
        final nonPinnedWidths = <double>[];

        for (var i = 0; i < cells.length; i++) {
          if (i == pinnedIndex) continue;
          nonPinnedCells.add(cells[i]);
          nonPinnedWidths.add(columnWidths[i]);
        }

        final baseDecoration = overlayDecoration ??
            BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 8,
                  offset: const Offset(1, 0),
                ),
              ],
            );
        final decoration = baseDecoration.copyWith(
          color: baseDecoration.color?.withOpacity(1) ??
              Theme.of(context).colorScheme.surface,
        );

        return Stack(
          children: [
            Row(
              children: [
                SizedBox(width: pinnedWidth),
                for (var i = 0; i < nonPinnedCells.length; i++)
                  SizedBox(width: nonPinnedWidths[i], child: nonPinnedCells[i]),
              ],
            ),
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: AnimatedBuilder(
                animation: horizontalController,
                builder: (context, child) {
                  final offset =
                      horizontalController.hasClients ? horizontalController.offset : 0.0;
                  return Transform.translate(
                    offset: Offset(-offset, 0),
                    child: child,
                  );
                },
                child: ClipRect(
                  child: Container(
                    width: pinnedWidth,
                    decoration: decoration,
                    child: pinnedCell,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class PinnedColumnSelector extends StatelessWidget {
  const PinnedColumnSelector({
    super.key,
    required this.columns,
    required this.selectedIndex,
    required this.onChanged,
    this.iconColor,
  });

  final List<String> columns;
  final int? selectedIndex;
  final ValueChanged<int?> onChanged;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopupMenuButton<int?>(
      tooltip: 'Pin a column',
      onSelected: onChanged,
      itemBuilder: (context) => [
        const PopupMenuItem<int?>(
          value: null,
          child: Text('None'),
        ),
        ...List.generate(columns.length, (index) {
          final isSelected = selectedIndex == index;
          return PopupMenuItem<int?>(
            value: index,
            child: Row(
              children: [
                Icon(
                  isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                  size: 18,
                  color: isSelected ? theme.colorScheme.primary : theme.iconTheme.color,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(columns[index])),
              ],
            ),
          );
        }),
      ],
      child: Icon(
        Icons.push_pin_outlined,
        size: 18,
        color: iconColor ?? theme.colorScheme.primary,
      ),
    );
  }
}
