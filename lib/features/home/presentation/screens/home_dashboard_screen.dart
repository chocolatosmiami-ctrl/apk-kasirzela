import '../../../../core/theme/minimal_ui.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_utils.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../inventory/presentation/providers/inventory_provider.dart';
import '../../../shift/presentation/providers/shift_provider.dart';
import '../../../subscription/presentation/providers/subscription_provider.dart';

typedef OnNavigate = void Function(int index);

class HomeDashboardScreen extends StatefulWidget {
  final OnNavigate onNavigate;
  final VoidCallback? onTapStok,
      onTapMeja,
      onTapRiwayat,
      onTapShift,
      onTapSubscription;
  const HomeDashboardScreen({
    super.key,
    required this.onNavigate,
    this.onTapStok,
    this.onTapMeja,
    this.onTapRiwayat,
    this.onTapShift,
    this.onTapSubscription,
  });

  @override
  State<HomeDashboardScreen> createState() => _HomeDashboardScreenState();
}

class _HomeDashboardScreenState extends State<HomeDashboardScreen> {
  VoidCallback? get onTapStok => widget.onTapStok;
  VoidCallback? get onTapMeja => widget.onTapMeja;
  VoidCallback? get onTapRiwayat => widget.onTapRiwayat;
  VoidCallback? get onTapShift => widget.onTapShift;
  VoidCallback? get onTapSubscription => widget.onTapSubscription;
  OnNavigate get onNavigate => widget.onNavigate;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final inventory = context.read<InventoryProvider>();
      if (!inventory.isLoading) inventory.loadIngredients();
    });
  }

  @override
  Widget build(BuildContext context) {
    final name = context.watch<AuthProvider>().currentUser?.name ?? 'Kasir';
    final shift = context.watch<ShiftProvider>().activeShift;
    final sub = context.watch<SubscriptionProvider>();
    final ingredients = context.watch<InventoryProvider>().ingredients;
    final attention = ingredients
        .where(
          (i) => i.currentStock != null && i.currentStock! <= (i.minStock ?? 0),
        )
        .toList();
    final now = DateTime.now();
    const months = [
      'Januari',
      'Februari',
      'Maret',
      'April',
      'Mei',
      'Juni',
      'Juli',
      'Agustus',
      'September',
      'Oktober',
      'November',
      'Desember',
    ];
    return Scaffold(
      backgroundColor: AppTheme.surfaceLight,
      body: ZelaPage(
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: () async {
              await Future.wait([
                context.read<ShiftProvider>().refreshLiveSales(),
                context.read<InventoryProvider>().loadIngredients(),
              ]);
            },
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 900),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(
                                  Icons.point_of_sale_rounded,
                                  color: AppTheme.primary,
                                ),
                                SizedBox(width: 10),
                                Text('Kasir Zela', style: AppTheme.headingLg),
                              ],
                            ),
                            const SizedBox(height: 28),
                            Text(
                              'Selamat bekerja, ${name.split(' ').first}',
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${now.day} ${months[now.month - 1]} ${now.year}',
                              style: const TextStyle(
                                fontSize: 14,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 24),
                            _Surface(
                              child: Row(
                                children: [
                                  Icon(
                                    shift == null
                                        ? Icons.schedule
                                        : Icons.check_circle_outline,
                                    color: AppTheme.primary,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          shift == null
                                              ? 'Shift belum dibuka'
                                              : 'Shift aktif',
                                          style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          shift == null
                                              ? 'Buka shift sebelum berjualan.'
                                              : '${shift.userName} · ${shift.durationText}',
                                          style: const TextStyle(
                                            fontSize: 14,
                                            color: AppTheme.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (onTapShift != null)
                                    TextButton(
                                      onPressed: onTapShift,
                                      child: Text(
                                        shift == null ? 'Buka shift' : 'Detail',
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            LayoutBuilder(
                              builder: (context, size) {
                                final width = size.maxWidth >= 420
                                    ? (size.maxWidth - 12) / 2
                                    : size.maxWidth;
                                return Wrap(
                                  spacing: 12,
                                  runSpacing: 12,
                                  children: [
                                    SizedBox(
                                      width: width,
                                      child: _Metric(
                                        label: 'Penjualan shift',
                                        value: shift == null
                                            ? '—'
                                            : AppUtils.formatCurrency(
                                                shift.totalSales,
                                              ),
                                        note: 'Sesuai ringkasan shift aktif',
                                        icon: Icons.payments_outlined,
                                      ),
                                    ),
                                    SizedBox(
                                      width: width,
                                      child: _Metric(
                                        label: 'Transaksi shift',
                                        value: shift == null
                                            ? '—'
                                            : '${shift.totalTransactions}',
                                        note:
                                            'Transaksi yang tercatat di shift',
                                        icon: Icons.receipt_long_outlined,
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                            const SizedBox(height: 28),
                            const Text(
                              'Akses cepat',
                              style: AppTheme.headingLg,
                            ),
                            const SizedBox(height: 14),
                            LayoutBuilder(
                              builder: (context, size) => Wrap(
                                spacing: 12,
                                runSpacing: 12,
                                children: [
                                  _QuickAction(
                                    width: (size.maxWidth - 12) / 2,
                                    icon: Icons.point_of_sale,
                                    title: 'Kasir',
                                    subtitle: 'Mulai pesanan',
                                    onTap: () => onNavigate(1),
                                  ),
                                  if (onTapMeja != null)
                                    _QuickAction(
                                      width: (size.maxWidth - 12) / 2,
                                      icon: Icons.table_restaurant_outlined,
                                      title: 'Meja',
                                      subtitle: 'Kelola pesanan meja',
                                      onTap: onTapMeja!,
                                    ),
                                  if (onTapStok != null)
                                    _QuickAction(
                                      width: (size.maxWidth - 12) / 2,
                                      icon: Icons.inventory_2_outlined,
                                      title: 'Stok',
                                      subtitle: 'Cek bahan baku',
                                      onTap: onTapStok!,
                                    ),
                                  if (onTapRiwayat != null)
                                    _QuickAction(
                                      width: (size.maxWidth - 12) / 2,
                                      icon: Icons.history,
                                      title: 'Riwayat',
                                      subtitle: 'Lihat transaksi',
                                      onTap: onTapRiwayat!,
                                    ),
                                ],
                              ),
                            ),
                            if (!sub.loading &&
                                (sub.isWarning || sub.isLocked)) ...[
                              const SizedBox(height: 24),
                              _Surface(
                                color: const Color(0xFFFFF4E5),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      sub.isLocked
                                          ? 'Saldo habis'
                                          : 'Saldo hampir habis',
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF845500),
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      sub.isLocked
                                          ? 'Isi saldo untuk melanjutkan berjualan.'
                                          : 'Tersisa ${sub.remainingTrx} transaksi.',
                                      style: const TextStyle(
                                        color: Color(0xFF845500),
                                      ),
                                    ),
                                    if (onTapSubscription != null)
                                      TextButton(
                                        onPressed: onTapSubscription,
                                        child: const Text('Isi saldo'),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                            const SizedBox(height: 28),
                            const Text(
                              'Perhatian stok',
                              style: AppTheme.headingLg,
                            ),
                            const SizedBox(height: 12),
                            _Surface(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        attention.isEmpty
                                            ? Icons.inventory_2_outlined
                                            : Icons.warning_amber_rounded,
                                        color: attention.isEmpty
                                            ? AppTheme.primary
                                            : const Color(0xFF845500),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          attention.isEmpty
                                              ? 'Tidak ada peringatan pada data stok yang dimuat.'
                                              : '${attention.length} bahan perlu diperiksa',
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  for (final ingredient in attention.take(3))
                                    Padding(
                                      padding: const EdgeInsets.only(top: 14),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              ingredient.name,
                                              style: const TextStyle(
                                                fontSize: 14,
                                              ),
                                            ),
                                          ),
                                          Text(
                                            'Sisa ${ingredient.currentStock}',
                                            style: const TextStyle(
                                              color: Color(0xFF845500),
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  if (onTapStok != null)
                                    TextButton(
                                      onPressed: onTapStok,
                                      child: const Text('Lihat stok'),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Surface extends StatelessWidget {
  final Widget child;
  final Color color;
  const _Surface({required this.child, this.color = Colors.white});
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppTheme.borderLight),
    ),
    child: child,
  );
}

class _Metric extends StatelessWidget {
  final String label, value, note;
  final IconData icon;
  const _Metric({
    required this.label,
    required this.value,
    required this.note,
    required this.icon,
  });
  @override
  Widget build(BuildContext context) => _Surface(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppTheme.primary, size: 22),
        const SizedBox(height: 12),
        Text(
          label,
          style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          note,
          style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary),
        ),
      ],
    ),
  );
}

class _QuickAction extends StatelessWidget {
  final double width;
  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;
  const _QuickAction({
    required this.width,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppTheme.borderLight),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 26, color: AppTheme.primary),
              const SizedBox(height: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
