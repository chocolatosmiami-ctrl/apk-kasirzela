import '../lib/core/services/recipe_stock.dart';

void check(bool ok, String message) {
  if (!ok) throw StateError(message);
}

void main() {
  final stock = {'ayam': 9.0, 'nasi': 3.0, 'air': 4.0};
  final recipes = <String, List<MapEntry<String, double>>>{
    'paket': [const MapEntry('ayam', 2), const MapEntry('nasi', 1)],
    'dobel': [const MapEntry('ayam', 2), const MapEntry('ayam', 2)],
    'air': [const MapEntry('air', 2)],
    'missing': [const MapEntry('belum diset', 1)],
    'invalid': [const MapEntry('ayam', 0)],
  };
  check(recipePortions('PAKET ', stock, recipes) == 3, 'Limit by scarcest ingredient');
  check(recipePortions('dobel', stock, recipes) == 2, 'Aggregate duplicate components');
  check(recipePortions('air', stock, recipes) == 2, 'Self recipe must not double deduct');
  check(recipePortions('nasi', stock, recipes) == 3, 'Direct stock supported');
  check(recipePortions('missing', stock, recipes) == null, 'Missing ingredient is unknown');
  check(recipePortions('unknown', stock, recipes) == null, 'Missing recipe is unknown');
  check(recipePortions('invalid', stock, recipes) == null, 'Invalid recipe cannot unlock');
  check(recipePortions('paket', {...stock, 'nasi': -1}, recipes) == 0, 'Negative locks');
  check(recipePortions('paket', {...stock, 'ayam': 1}, recipes) == 0, 'Below recipe requirement locks');
  print('PASS: recipe portions, bottleneck, duplicates, self recipe, unknown and depleted stock');
}
