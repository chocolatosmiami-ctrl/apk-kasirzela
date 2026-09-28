import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../../../../core/utils/app_utils.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../orders/presentation/providers/orders_provider.dart';
import '../../../subscription/presentation/providers/subscription_provider.dart';

class AiChatScreen extends StatefulWidget {
  const AiChatScreen({super.key});
  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen>
    with TickerProviderStateMixin {
  // ── API config ───────────────────────────────────────────
  static const _apiKey =
      'sk-XhMUeyZyQSw1nmoXoH3pOgaXhklUunnOtS9fY7Na8fOXFonE';
  static const _baseUrl = 'https://api.cometapi.com/v1';
  static const _model = 'gpt-4.1-mini';

  final _scrollCtrl = ScrollController();
  final _textCtrl = TextEditingController();
  final _focusNode = FocusNode();
  final List<_ChatMessage> _messages = [];
  bool _isTyping = false;
  late AnimationController _typingAnim;

  // Konteks bisnis yang dikirim ke AI
  String _businessContext = '';

  @override
  void initState() {
    super.initState();
    _typingAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _buildContext();
      _sendWelcome();
    });
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    _textCtrl.dispose();
    _focusNode.dispose();
    _typingAnim.dispose();
    super.dispose();
  }

  // ── Bangun konteks bisnis dari providers ─────────────────
  Future<void> _buildContext() async {
    final auth = context.read<AuthProvider>();
    final sub = context.read<SubscriptionProvider>();
    final ord = context.read<OrdersProvider>();

    final name = auth.currentUser?.name ?? 'Pemilik';
    final branch = auth.currentUser?.branchName ?? 'Cabang';
    final role = auth.currentUser?.role ?? 'owner';
    final balance = AppUtils.formatCurrency(sub.balance);
    final remaining = sub.remainingTrx;

    // Hitung omset hari ini
    final today = DateTime.now();
    final todayOrders = ord.orders.where((o) {
      final d = AppUtils.safeParseDate(o.createdAt);
      return d.year == today.year && d.month == today.month &&
          d.day == today.day && o.status != 'cancelled';
    }).toList();
    final omset = todayOrders.fold<double>(0, (s, o) => s + o.total);
    final trxCount = todayOrders.length;

    _businessContext = '''
Kamu adalah Zela, AI Bisnis Assistant untuk aplikasi Kasir Zela POS.
Kamu membantu pemilik dan manajer restoran di Indonesia menganalisis bisnis mereka.

PROFIL PENGGUNA:
- Nama: $name
- Role: $role  
- Cabang: $branch

DATA BISNIS HARI INI:
- Omset: ${AppUtils.formatCurrency(omset)}
- Jumlah transaksi: $trxCount
- Saldo aplikasi: $balance (sisa $remaining trx)

KEPRIBADIAN:
- Gunakan bahasa Indonesia yang ramah, profesional, dan to-the-point
- Berikan insight bisnis yang actionable dan spesifik
- Jika ditanya data yang tidak kamu punya, jujur dan sarankan cara mendapatkannya
- Gunakan emoji secukupnya untuk membuat percakapan lebih menarik
- Sebut pengguna dengan nama "$name" sesekali
- Fokus pada: analisis penjualan, tips operasional restoran, strategi peningkatan omset

Mulai percakapan dengan sapaan hangat dan tawaran bantuan.
''';
  }

  // ── Welcome message dari AI ───────────────────────────────
  Future<void> _sendWelcome() async {
    await _buildContext();
    final auth = context.read<AuthProvider>();
    final name = auth.currentUser?.name?.split(' ').first ?? 'Kak';
    final now = DateTime.now();
    final greeting = now.hour < 11
        ? 'Selamat pagi'
        : now.hour < 15
            ? 'Selamat siang'
            : now.hour < 18
                ? 'Selamat sore'
                : 'Selamat malam';

    setState(() => _isTyping = true);
    await Future.delayed(const Duration(milliseconds: 800));

    if (!mounted) return;
    setState(() {
      _isTyping = false;
      _messages.add(_ChatMessage(
        text: '$greeting, $name! 👋\n\n'
            'Saya **Zela**, AI Bisnis Assistant kamu.\n\n'
            'Saya bisa bantu kamu dengan:\n'
            '• 📊 Analisis omset & performa penjualan\n'
            '• 💡 Tips meningkatkan pendapatan restoran\n'
            '• 🍽️ Strategi menu & pricing\n'
            '• 📋 Laporan & insight bisnis\n\n'
            'Ada yang bisa saya bantu hari ini?',
        isUser: false,
        time: DateTime.now(),
      ));
    });
    _scrollToBottom();
  }

  // ── Kirim pesan ke API ────────────────────────────────────
  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty || _isTyping) return;

    final userMsg = text.trim();
    _textCtrl.clear();

    setState(() {
      _messages.add(_ChatMessage(
        text: userMsg,
        isUser: true,
        time: DateTime.now(),
      ));
      _isTyping = true;
    });
    _scrollToBottom();

    try {
      // Build message history (max 20 pesan terakhir untuk hemat token)
      final history = _messages
          .where((m) => !m.isError)
          .take(20)
          .map((m) => {
                'role': m.isUser ? 'user' : 'assistant',
                'content': m.text,
              })
          .toList();

      final response = await http.post(
        Uri.parse('$_baseUrl/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_apiKey',
        },
        body: jsonEncode({
          'model': _model,
          'messages': [
            {'role': 'system', 'content': _businessContext},
            ...history,
          ],
          'max_tokens': 1000,
          'temperature': 0.7,
          'stream': false,
        }),
      ).timeout(const Duration(seconds: 30));

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final reply = data['choices'][0]['message']['content'] as String;

        setState(() {
          _isTyping = false;
          _messages.add(_ChatMessage(
            text: reply.trim(),
            isUser: false,
            time: DateTime.now(),
          ));
        });
      } else {
        final err = jsonDecode(response.body);
        throw Exception(err['error']?['message'] ?? 'Error ${response.statusCode}');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isTyping = false;
        _messages.add(_ChatMessage(
          text: 'Maaf, ada gangguan koneksi. Coba lagi ya 🙏\n\n_${e.toString()}_',
          isUser: false,
          time: DateTime.now(),
          isError: true,
        ));
      });
    }

    _scrollToBottom();
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _clearChat() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Hapus Percakapan?',
            style: TextStyle(fontWeight: FontWeight.w800)),
        content: const Text('Semua pesan akan dihapus dan percakapan dimulai ulang.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Batal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00897B),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10))),
            onPressed: () {
              Navigator.pop(ctx);
              setState(() => _messages.clear());
              _sendWelcome();
            },
            child: const Text('Hapus', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // ── Quick prompts ─────────────────────────────────────────
  static const _quickPrompts = [
    ('📊', 'Analisis omset hari ini'),
    ('💡', 'Tips tingkatkan penjualan'),
    ('🍽️', 'Rekomendasi strategi menu'),
    ('📈', 'Cara naikan rata-rata transaksi'),
    ('⏰', 'Jam tersibuk restoran saya'),
    ('💰', 'Tips kelola pengeluaran'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5FAFA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF111111),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded,
              color: Color(0xFF00897B), size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF00897B), Color(0xFF26A69A)],
              ),
              shape: BoxShape.circle,
            ),
            child: const Center(
                child: Text('🤖', style: TextStyle(fontSize: 18))),
          ),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Zela AI',
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: Color(0xFF111111))),
            Row(children: [
              Container(
                width: 6, height: 6,
                decoration: const BoxDecoration(
                    color: Color(0xFF26A69A), shape: BoxShape.circle),
              ),
              const SizedBox(width: 4),
              const Text('Online · AI Bisnis Assistant',
                  style: TextStyle(
                      fontSize: 10, color: Color(0xFF9CA3AF))),
            ]),
          ]),
        ]),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded,
                color: Color(0xFF9CA3AF)),
            tooltip: 'Hapus percakapan',
            onPressed: _clearChat,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          // ── Chat messages ────────────────────────────────
          Expanded(
            child: _messages.isEmpty
                ? const Center(
                    child: CircularProgressIndicator(
                        color: Color(0xFF00897B)))
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    itemCount: _messages.length + (_isTyping ? 1 : 0),
                    itemBuilder: (ctx, i) {
                      if (i == _messages.length) {
                        return _TypingIndicator(anim: _typingAnim);
                      }
                      final msg = _messages[i];
                      return _MessageBubble(msg: msg);
                    },
                  ),
          ),

          // ── Quick prompts (hanya muncul kalau pesan sedikit) ──
          if (_messages.length <= 2)
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _quickPrompts.map((p) => GestureDetector(
                    onTap: () => _sendMessage(p.$2),
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE0F7F4),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: const Color(0xFFB2DFDB)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(p.$1,
                              style: const TextStyle(fontSize: 13)),
                          const SizedBox(width: 5),
                          Text(p.$2,
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF00897B),
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  )).toList(),
                ),
              ),
            ),

          // ── Input bar ────────────────────────────────────
          Container(
            color: Colors.white,
            padding: EdgeInsets.fromLTRB(
                12, 8, 12,
                MediaQuery.of(context).viewInsets.bottom +
                    MediaQuery.of(context).padding.bottom +
                    8),
            child: Row(children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5FAFA),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: const Color(0xFFE0F2F1)),
                  ),
                  child: TextField(
                    controller: _textCtrl,
                    focusNode: _focusNode,
                    maxLines: 4,
                    minLines: 1,
                    textCapitalization: TextCapitalization.sentences,
                    style: const TextStyle(
                        fontSize: 13, color: Color(0xFF111111)),
                    decoration: const InputDecoration(
                      hintText: 'Tanya sesuatu tentang bisnis kamu...',
                      hintStyle: TextStyle(
                          color: Color(0xFFBBBBBB), fontSize: 13),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                    ),
                    onSubmitted: (v) => _sendMessage(v),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Tombol kirim
              GestureDetector(
                onTap: () => _sendMessage(_textCtrl.text),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: _isTyping
                        ? const Color(0xFFB2DFDB)
                        : const Color(0xFF00897B),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _isTyping
                        ? Icons.hourglass_top_rounded
                        : Icons.send_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

// ── Message Bubble ───────────────────────────────────────────
class _MessageBubble extends StatelessWidget {
  final _ChatMessage msg;
  const _MessageBubble({required this.msg});

  @override
  Widget build(BuildContext context) {
    final isUser = msg.isUser;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            Container(
              width: 28, height: 28,
              margin: const EdgeInsets.only(right: 8),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                    colors: [Color(0xFF00897B), Color(0xFF26A69A)]),
                shape: BoxShape.circle,
              ),
              child: const Center(
                  child: Text('🤖', style: TextStyle(fontSize: 14))),
            ),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isUser
                    ? const Color(0xFF00897B)
                    : msg.isError
                        ? const Color(0xFFFEF2F2)
                        : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isUser ? 18 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 18),
                ),
                border: isUser
                    ? null
                    : Border.all(
                        color: msg.isError
                            ? const Color(0xFFFCA5A5)
                            : const Color(0xFFE8F5F3)),
              ),
              child: _buildText(msg.text, isUser, msg.isError),
            ),
          ),
          if (isUser) const SizedBox(width: 4),
        ],
      ),
    );
  }

  // Render bold **text** dan newlines
  Widget _buildText(String text, bool isUser, bool isError) {
    final spans = <TextSpan>[];
    final parts = text.split('**');
    for (int i = 0; i < parts.length; i++) {
      spans.add(TextSpan(
        text: parts[i],
        style: TextStyle(
          fontWeight: i % 2 == 1 ? FontWeight.w700 : FontWeight.normal,
          fontSize: 13,
          height: 1.5,
          color: isUser
              ? Colors.white
              : isError
                  ? const Color(0xFFDC2626)
                  : const Color(0xFF111111),
        ),
      ));
    }
    return RichText(text: TextSpan(children: spans));
  }
}

// ── Typing indicator ─────────────────────────────────────────
class _TypingIndicator extends StatelessWidget {
  final AnimationController anim;
  const _TypingIndicator({required this.anim});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            width: 28, height: 28,
            margin: const EdgeInsets.only(right: 8),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                  colors: [Color(0xFF00897B), Color(0xFF26A69A)]),
              shape: BoxShape.circle,
            ),
            child: const Center(
                child: Text('🤖', style: TextStyle(fontSize: 14))),
          ),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(18),
                topRight: Radius.circular(18),
                bottomRight: Radius.circular(18),
                bottomLeft: Radius.circular(4),
              ),
              border: Border.all(color: const Color(0xFFE8F5F3)),
            ),
            child: AnimatedBuilder(
              animation: anim,
              builder: (_, __) => Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(3, (i) {
                  final delay = i * 0.2;
                  final opacity = ((anim.value - delay).clamp(0.0, 1.0));
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    width: 7, height: 7,
                    decoration: BoxDecoration(
                      color: Color.fromRGBO(
                          0, 137, 123, 0.3 + opacity * 0.7),
                      shape: BoxShape.circle,
                    ),
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Data model ────────────────────────────────────────────────
class _ChatMessage {
  final String text;
  final bool isUser;
  final bool isError;
  final DateTime time;
  const _ChatMessage({
    required this.text,
    required this.isUser,
    required this.time,
    this.isError = false,
  });
}
