import 'package:flutter/material.dart';

/// The permission-filtered destination list stays owned by HomeScreen.
/// This widget only presents the list and forwards user selections.
class ZelaNavigation extends StatelessWidget {
  final List<NavigationDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final VoidCallback onOverflow;

  const ZelaNavigation({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
    required this.onOverflow,
  });

  @override
  Widget build(BuildContext context) {
    final overflow = destinations.length > 4;
    final visibleCount = overflow ? 4 : destinations.length;
    final index = selectedIndex.clamp(0, destinations.length - 1);
    return NavigationBar(
      height:
          72 + (MediaQuery.textScalerOf(context).scale(14) - 14).clamp(0, 28),
      animationDuration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 150),
      selectedIndex: overflow && index >= 4 ? 4 : index,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      onDestinationSelected: (value) {
        if (value == visibleCount) {
          onOverflow();
        } else {
          onSelected(value);
        }
      },
      destinations: [
        ...destinations.take(visibleCount),
        NavigationDestination(
          icon: const Icon(Icons.apps_rounded),
          label: overflow ? 'Lainnya' : 'Menu',
        ),
      ],
    );
  }
}
