import 'package:flutter/rendering.dart';

/// Chooses columns from the space actually assigned to the product pane.
/// Unlike max-cross-axis grids this guarantees a minimum usable item width.
class ZelaProductGridDelegate extends SliverGridDelegate {
  final double minItemWidth;
  final double mainAxisExtent;
  final double spacing;
  const ZelaProductGridDelegate({
    required this.minItemWidth,
    required this.mainAxisExtent,
    this.spacing = 12,
  });

  @override
  SliverGridLayout getLayout(SliverConstraints constraints) {
    final count =
        ((constraints.crossAxisExtent + spacing) / (minItemWidth + spacing))
            .floor()
            .clamp(1, 12);
    return SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: count,
      mainAxisExtent: mainAxisExtent,
      mainAxisSpacing: spacing,
      crossAxisSpacing: spacing,
    ).getLayout(constraints);
  }

  @override
  bool shouldRelayout(ZelaProductGridDelegate oldDelegate) =>
      minItemWidth != oldDelegate.minItemWidth ||
      mainAxisExtent != oldDelegate.mainAxisExtent ||
      spacing != oldDelegate.spacing;
}
