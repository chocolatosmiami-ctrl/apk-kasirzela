import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/utils/app_utils.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../inventory/presentation/providers/inventory_provider.dart';
import '../../../shift/presentation/providers/shift_provider.dart';
import '../../../subscription/presentation/providers/subscription_provider.dart';

typedef OnNavigate = void Function(int index);

class HomeDashboardScreen extends StatefulWidget {
  final OnNavigate onNavigate;
  final VoidCallback? onTapStok;
  const HomeDashboardScreen({super.key, required this.onNavigate, this.onTapStok});
  @override
  State<HomeDashboardScreen> createState() => _HomeDashboardScreenState();
}

class _HomeDashboardScreenState extends State<HomeDashboardScreen>
    with SingleTickerProviderStateMixin {
  final PageController _bannerCtrl = PageController();
  int _bannerIndex = 0;
  Timer? _bannerTimer;
  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;

  static const List<_PromoItem> _promos = [
    _PromoItem(emoji: '🤖', title: 'AI Bisnis Insights',
        subtitle: 'Analisis omset & tren penjualan otomatis',
        color: Color(0xFF00897B), lightColor: Color(0xFFE0F7F4)),
    _PromoItem(emoji: '🏷️', title: 'Diskon Fleksibel',
        subtitle: 'Atur promo per-cabang, nominal atau persen',
        color: Color(0xFF1565C0), lightColor: Color(0xFFE3F2FD)),
    _PromoItem(emoji: '🖨️', title: 'Auto Cetak Struk',
        subtitle: 'Struk thermal otomatis setelah transaksi',
        color: Color(0xFF6A1B9A), lightColor: Color(0xFFF3E5F5)),
    _PromoItem(emoji: '📊', title: 'Laporan PDF Otomatis',
        subtitle: 'Laporan harian dikirim otomatis jam 22:00',
        color: Color(0xFF00695C), lightColor: Color(0xFFE0F7F4)),
    _PromoItem(emoji: '📦', title: 'Kelola Stok Bahan',
        subtitle: 'Tracking bahan baku terhubung ke menu',
        color: Color(0xFF4E342E), lightColor: Color(0xFFF5F0EB)),
  ];

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800));
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _animCtrl.forward();
    _startTimer();
  }

  @override
  void dispose() {
    _bannerTimer?.cancel();
    _bannerCtrl.dispose();
    _animCtrl.dispose();
    super.dispose();
  }

  void _startTimer() {
    _bannerTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || !_bannerCtrl.hasClients) return;
      final next = (_bannerIndex + 1) % _promos.length;
      _bannerCtrl.animateToPage(next,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut);
    });
  }


  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final name = auth.currentUser?.name ?? 'Pengguna';
    final now = DateTime.now();
    final months = ['Jan','Feb','Mar','Apr','Mei','Jun','Jul','Agu','Sep','Okt','Nov','Des'];
    final days = ['Minggu','Senin','Selasa','Rabu','Kamis','Jumat','Sabtu'];
    final dateStr = '${days[now.weekday % 7]}, ${now.day} ${months[now.month - 1]} ${now.year}';

    return Scaffold(
      backgroundColor: const Color(0xFFF5FAFA),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: RefreshIndicator(
          color: const Color(0xFF00897B),
          onRefresh: () async {
            // Tidak ada stats yang perlu di-refresh untuk kasir
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics()),
            slivers: [

              // ── SliverAppBar sticky putih bersih ──────────
              SliverAppBar(
                pinned: true,
                floating: false,
                backgroundColor: Colors.white,
                surfaceTintColor: Colors.transparent,
                elevation: 0,
                automaticallyImplyLeading: false,
                expandedHeight: 0,
                toolbarHeight: 68,
                flexibleSpace: FlexibleSpaceBar(
                  background: Container(
                    color: Colors.white,
                    padding: EdgeInsets.fromLTRB(
                        16, MediaQuery.of(context).padding.top + 10, 16, 8),
                    child: Row(children: [
                      // Avatar teal
                      Container(
                        width: 44, height: 44,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF00897B), Color(0xFF26A69A)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            name.isNotEmpty ? name[0].toUpperCase() : '?',
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w800,
                                color: Colors.white),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Row(children: [
                              Text('Hello, ', style: TextStyle(
                                  fontSize: 14, color: Colors.grey[500])),
                              Text(name.split(' ').first,
                                  style: const TextStyle(
                                      fontSize: 14, fontWeight: FontWeight.w800,
                                      color: Color(0xFF111111))),
                              const Text(' 👋',
                                  style: TextStyle(fontSize: 14)),
                            ]),
                            Text(dateStr,
                                style: const TextStyle(
                                    fontSize: 11, color: Color(0xFF9CA3AF))),
                          ],
                        ),
                      ),
                      // Icon buttons
                      Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF5FAFA),
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFFE0F2F1)),
                        ),
                        child: const Icon(Icons.chat_bubble_outline_rounded,
                            size: 18, color: Color(0xFF00897B)),
                      ),
                      const SizedBox(width: 8),
                      Stack(children: [
                        Container(
                          width: 36, height: 36,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF5FAFA),
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0xFFE0F2F1)),
                          ),
                          child: const Icon(Icons.notifications_none_rounded,
                              size: 18, color: Color(0xFF9CA3AF)),
                        ),
                        Positioned(right: 0, top: 0,
                          child: Container(
                            width: 10, height: 10,
                            decoration: const BoxDecoration(
                                color: Color(0xFFEF4444),
                                shape: BoxShape.circle),
                          ),
                        ),
                      ]),
                    ]),
                  ),
                ),
              ),

              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [

                    // ── Search bar ─────────────────────────
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      child: Container(
                        height: 46,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFE0F2F1)),
                        ),
                        child: Row(children: [
                          const SizedBox(width: 14),
                          const Icon(Icons.search_rounded,
                              color: Color(0xFF26A69A), size: 20),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text('Cari menu, laporan, fitur...',
                                style: TextStyle(
                                    color: Color(0xFFBBBBBB), fontSize: 13)),
                          ),
                          Container(
                            width: 36, height: 36,
                            margin: const EdgeInsets.only(right: 5),
                            decoration: BoxDecoration(
                              color: const Color(0xFF00897B),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.mic_none_rounded,
                                color: Colors.white, size: 18),
                          ),
                        ]),
                      ),
                    ),

                    // ── Quick menu 4 icon ──────────────────
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _QuickBtn(emoji: '🧾', label: 'Kasir',
                              bg: const Color(0xFFE0F7F4),
                              onTap: () => widget.onNavigate(1)),
                          _QuickBtn(emoji: '📊', label: 'Laporan',
                              bg: const Color(0xFFE8F0FE),
                              onTap: () => widget.onNavigate(2)),
                          _QuickBtn(emoji: '📦', label: 'Stok',
                              bg: const Color(0xFFFFF3E0),
                              onTap: () => widget.onTapStok?.call()),
                          _QuickBtn(emoji: '⏱️', label: 'Shift',
                              bg: const Color(0xFFFCE4EC),
                              onTap: () => widget.onNavigate(4)),
                        ],
                      ),
                    ),


                    // ── Saldo alert ────────────────────────
                    Consumer<SubscriptionProvider>(
                      builder: (ctx, sub, _) {
                        if (sub.loading || (!sub.isWarning && !sub.isLocked))
                          return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 11),
                            decoration: BoxDecoration(
                              color: sub.isLocked
                                  ? const Color(0xFFFEF2F2)
                                  : const Color(0xFFFFFBEB),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: sub.isLocked
                                  ? const Color(0xFFFCA5A5)
                                  : const Color(0xFFFCD34D)),
                            ),
                            child: Row(children: [
                              Icon(sub.isLocked
                                  ? Icons.lock_outline_rounded
                                  : Icons.warning_amber_rounded,
                                  color: sub.isLocked
                                      ? const Color(0xFFEF4444)
                                      : const Color(0xFFF59E0B),
                                  size: 20),
                              const SizedBox(width: 10),
                              Expanded(child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    sub.isLocked ? 'Saldo Habis!' : 'Saldo Hampir Habis',
                                    style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12,
                                        color: sub.isLocked
                                            ? const Color(0xFFDC2626)
                                            : const Color(0xFFD97706)),
                                  ),
                                  Text(
                                    sub.isLocked
                                        ? 'Top up untuk melanjutkan berjualan'
                                        : 'Sisa ${sub.remainingTrx} transaksi lagi',
                                    style: const TextStyle(
                                        fontSize: 11,
                                        color: Color(0xFF9CA3AF)),
                                  ),
                                ],
                              )),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: sub.isLocked
                                      ? const Color(0xFFEF4444)
                                      : const Color(0xFFF59E0B),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Text('Top Up',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700)),
                              ),
                            ]),
                          ),
                        );
                      },
                    ),

                    // ── Banner promo slide ─────────────────
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 140,
                      child: PageView.builder(
                        controller: _bannerCtrl,
                        itemCount: _promos.length,
                        onPageChanged: (i) =>
                            setState(() => _bannerIndex = i),
                        itemBuilder: (ctx, i) =>
                            _BannerCard(promo: _promos[i]),
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Dots
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(_promos.length, (i) =>
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            width: _bannerIndex == i ? 22 : 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: _bannerIndex == i
                                  ? const Color(0xFF00897B)
                                  : const Color(0xFFB2DFDB),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          )),
                    ),

                    // ── Shift aktif ────────────────────────
                    Consumer<ShiftProvider>(
                      builder: (ctx, sp, _) {
                        if (!sp.hasActiveShift) return const SizedBox.shrink();
                        final shift = sp.activeShift!;
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                          child: _SectionCard(
                            icon: Icons.av_timer_rounded,
                            iconBg: const Color(0xFFE0F7F4),
                            iconColor: const Color(0xFF00897B),
                            title: 'Shift Aktif',
                            subtitle:
                            '${shift.userName} · Modal ${AppUtils.formatCurrency(shift.openingCash)}',
                            action: 'Detail',
                            onAction: () => widget.onNavigate(4),
                          ),
                        );
                      },
                    ),

                    // ── Stok hampir habis ──────────────────
                    Consumer<InventoryProvider>(
                      builder: (ctx, inv, _) {
                        final low = inv.ingredients.where((i) =>
                        i.currentStock != null && i.minStock != null &&
                            i.currentStock! <= i.minStock! &&
                            i.currentStock! > 0).take(3).toList();
                        final out = inv.ingredients.where((i) =>
                        i.currentStock != null &&
                            i.currentStock! <= 0).take(2).toList();
                        if (low.isEmpty && out.isEmpty)
                          return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                const Text('⚠️ Peringatan Stok',
                                    style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF111111))),
                                const Spacer(),
                                GestureDetector(
                                  onTap: () => widget.onTapStok?.call(),
                                  child: const Text('Lihat semua ›',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: Color(0xFF00897B),
                                          fontWeight: FontWeight.w600)),
                                ),
                              ]),
                              const SizedBox(height: 10),
                              ...out.map((i) => _StokRow(
                                  nama: i.name,
                                  stok: i.currentStock ?? 0,
                                  isHabis: true)),
                              ...low.map((i) => _StokRow(
                                  nama: i.name,
                                  stok: i.currentStock ?? 0,
                                  isHabis: false)),
                            ],
                          ),
                        );
                      },
                    ),

                    // ── Hero AI banner ─────────────────────
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF00897B), Color(0xFF00695C)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Stack(
                          children: [
                            Positioned(right: -20, top: -20,
                              child: Container(
                                width: 120, height: 120,
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.05),
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                            Positioned(right: 20, bottom: -30,
                              child: Container(
                                width: 80, height: 80,
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.04),
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(18),
                              child: Row(children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.2),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: const Text('AI Powered',
                                            style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 10,
                                                fontWeight: FontWeight.w700)),
                                      ),
                                      const SizedBox(height: 10),
                                      const Text('Kasir Zela',
                                          style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 22,
                                              fontWeight: FontWeight.w900,
                                              letterSpacing: -0.5)),
                                      const Text('AI Bisnis Insights',
                                          style: TextStyle(
                                              color: Colors.white70,
                                              fontSize: 12)),
                                      const SizedBox(height: 14),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 16, vertical: 9),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(22),
                                        ),
                                        child: const Text('Chat dengan AI Zela',
                                            style: TextStyle(
                                                color: Color(0xFF00897B),
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700)),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                const Text('🤖',
                                    style: TextStyle(fontSize: 56)),
                              ]),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 28),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Helper Widgets ───────────────────────────────────────────

class _QuickBtn extends StatelessWidget {
  final String emoji, label;
  final Color bg;
  final VoidCallback onTap;
  const _QuickBtn({required this.emoji, required this.label,
    required this.bg, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Column(children: [
      Container(
        width: 60, height: 60,
        decoration: BoxDecoration(
          color: bg, borderRadius: BorderRadius.circular(18),
          border: Border.all(color: bg.withOpacity(0.5)),
        ),
        child: Center(child: Text(emoji,
            style: const TextStyle(fontSize: 26))),
      ),
      const SizedBox(height: 7),
      Text(label, style: const TextStyle(
          fontSize: 11, fontWeight: FontWeight.w600,
          color: Color(0xFF374151))),
    ]),
  );
}


class _BannerCard extends StatelessWidget {
  final _PromoItem promo;
  const _BannerCard({required this.promo});
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 16),
    decoration: BoxDecoration(
      color: promo.lightColor,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: promo.color.withOpacity(0.15)),
    ),
    child: Stack(children: [
      Positioned(right: -10, top: -10,
        child: Container(
          width: 90, height: 90,
          decoration: BoxDecoration(
              color: promo.color.withOpacity(0.08),
              shape: BoxShape.circle),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Row(children: [
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: promo.color.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('Fitur Terbaru',
                        style: TextStyle(color: promo.color,
                            fontSize: 9, fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(height: 8),
                  Text(promo.title,
                      style: TextStyle(color: promo.color,
                          fontSize: 17, fontWeight: FontWeight.w800,
                          letterSpacing: -0.3)),
                  const SizedBox(height: 4),
                  Text(promo.subtitle,
                      style: TextStyle(
                          color: promo.color.withOpacity(0.65), fontSize: 11),
                      maxLines: 2),
                ]),
          ),
          const SizedBox(width: 12),
          Text(promo.emoji, style: const TextStyle(fontSize: 48)),
        ]),
      ),
    ]),
  );
}

class _SectionCard extends StatelessWidget {
  final IconData icon;
  final Color iconBg, iconColor;
  final String title, subtitle, action;
  final VoidCallback onAction;
  const _SectionCard({required this.icon, required this.iconBg,
    required this.iconColor, required this.title, required this.subtitle,
    required this.action, required this.onAction});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFE8F5F3)),
    ),
    child: Row(children: [
      Container(
        width: 42, height: 42,
        decoration: BoxDecoration(color: iconBg,
            borderRadius: BorderRadius.circular(12)),
        child: Icon(icon, color: iconColor, size: 22),
      ),
      const SizedBox(width: 12),
      Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(
            fontSize: 11, color: Color(0xFF9CA3AF))),
        Text(subtitle, style: const TextStyle(
            fontSize: 13, fontWeight: FontWeight.w700,
            color: Color(0xFF111111))),
      ])),
      GestureDetector(
        onTap: onAction,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFFE0F7F4),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(action, style: const TextStyle(
              fontSize: 11, color: Color(0xFF00897B),
              fontWeight: FontWeight.w700)),
        ),
      ),
    ]),
  );
}

class _StokRow extends StatelessWidget {
  final String nama;
  final double stok;
  final bool isHabis;
  const _StokRow({required this.nama, required this.stok,
    required this.isHabis});
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 7),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: isHabis ? const Color(0xFFFEF2F2) : const Color(0xFFFFFBEB),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
          color: isHabis ? const Color(0xFFFCA5A5)
              : const Color(0xFFFCD34D)),
    ),
    child: Row(children: [
      Icon(isHabis ? Icons.cancel_outlined
          : Icons.warning_amber_outlined,
          color: isHabis ? const Color(0xFFEF4444)
              : const Color(0xFFF59E0B),
          size: 18),
      const SizedBox(width: 10),
      Expanded(child: Text(nama,
          style: const TextStyle(
              fontSize: 13, fontWeight: FontWeight.w600,
              color: Color(0xFF111111)))),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: isHabis ? const Color(0xFFEF4444)
              : const Color(0xFFF59E0B),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(isHabis ? 'Habis' : 'Sisa ${stok.toInt()}',
            style: const TextStyle(
                fontSize: 10, fontWeight: FontWeight.w700,
                color: Colors.white)),
      ),
    ]),
  );
}

class _PromoItem {
  final String emoji, title, subtitle;
  final Color color, lightColor;
  const _PromoItem({required this.emoji, required this.title,
    required this.subtitle, required this.color, required this.lightColor});
}