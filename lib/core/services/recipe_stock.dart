/// Shared recipe arithmetic for menu badges, locks and cart validation.
Map<String, double> recipeNeeds(String menu, Map<String, double> stock,
    Map<String, List<MapEntry<String, double>>> recipes) {
  final key = menu.toLowerCase().trim();
  final parts = recipes[key] ?? const <MapEntry<String, double>>[];
  final needs = <String, double>{};
  if (stock.containsKey(key) && !parts.any((p) => p.key == key)) {
    needs[key] = 1;
  }
  for (final part in parts) {
    needs[part.key] = (needs[part.key] ?? 0) + part.value;
  }
  return needs;
}

/// null means unknown/unconfigured, not unlimited stock.
int? recipePortions(String menu, Map<String, double> stock,
    Map<String, List<MapEntry<String, double>>> recipes) {
  final needs = recipeNeeds(menu, stock, recipes);
  if (needs.isEmpty) return null;
  int? portions;
  for (final need in needs.entries) {
    final available = stock[need.key];
    if (available == null || !available.isFinite ||
        !need.value.isFinite || need.value <= 0) return null;
    final count = (available / need.value).floor();
    final safe = count < 0 ? 0 : count;
    if (portions == null || safe < portions) portions = safe;
  }
  return portions;
}
