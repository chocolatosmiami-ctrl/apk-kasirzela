import 'package:flutter/material.dart';
import 'app_theme.dart';

/// Keeps existing scroll/controller behavior and gives tablet pages a readable width.
class ZelaPage extends StatelessWidget {
  final Widget child;
  const ZelaPage({super.key, required this.child});
  @override
  Widget build(BuildContext context) => ColoredBox(
    color: AppTheme.surfaceLight,
    child: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: SizedBox(
          width: double.infinity,
          height: double.infinity,
          child: child,
        ),
      ),
    ),
  );
}

class ZelaAuthBody extends StatelessWidget {
  final Widget child;
  const ZelaAuthBody({super.key, required this.child});
  @override
  Widget build(BuildContext context) => SafeArea(
    child: LayoutBuilder(
      builder: (context, size) => SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: (size.maxHeight - 48).clamp(0, double.infinity),
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: child,
            ),
          ),
        ),
      ),
    ),
  );
}

class ZelaBrand extends StatelessWidget {
  const ZelaBrand({super.key});
  @override
  Widget build(BuildContext context) => const Column(
    children: [
      Icon(Icons.point_of_sale_rounded, color: AppTheme.primary, size: 44),
      SizedBox(height: 10),
      Text(
        'Kasir Zela',
        style: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: AppTheme.textPrimary,
        ),
      ),
    ],
  );
}

class ZelaPinPanel extends StatelessWidget {
  final String title, subtitle, name, pin, error, actionLabel;
  final bool busy;
  final ValueChanged<String> onDigit;
  final VoidCallback onErase;
  final VoidCallback? onSubmit;
  final Widget? footer;
  const ZelaPinPanel({
    super.key,
    required this.title,
    required this.subtitle,
    required this.name,
    required this.pin,
    required this.onDigit,
    required this.onErase,
    required this.onSubmit,
    this.error = '',
    this.busy = false,
    this.actionLabel = 'Lanjutkan',
    this.footer,
  });

  @override
  Widget build(BuildContext context) => ZelaAuthBody(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const ZelaBrand(),
        const SizedBox(height: 28),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 18),
        CircleAvatar(
          radius: 26,
          backgroundColor: AppTheme.primarySurface,
          child: Text(
            name.isEmpty ? '?' : name[0].toUpperCase(),
            style: const TextStyle(fontSize: 22, color: AppTheme.primaryDark),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          name,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 14,
            height: 1.4,
            color: AppTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 24),
        Semantics(
          label: '${pin.length} digit PIN terisi',
          child: ExcludeSemantics(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                6,
                (i) => Container(
                  width: 14,
                  height: 14,
                  margin: const EdgeInsets.symmetric(horizontal: 7),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i < pin.length
                        ? AppTheme.primary
                        : Colors.transparent,
                    border: Border.all(
                      color: error.isEmpty ? AppTheme.primary : AppTheme.danger,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (error.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Semantics(
              liveRegion: true,
              child: Text(
                error,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.danger, fontSize: 14),
              ),
            ),
          ),
        const SizedBox(height: 24),
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
          ['', '0', 'erase'],
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                for (final digit in row)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      child: digit.isEmpty
                          ? const SizedBox(height: 56)
                          : OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(0, 56),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                foregroundColor: AppTheme.textPrimary,
                                backgroundColor: Colors.white,
                                side: const BorderSide(
                                  color: AppTheme.borderLight,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: busy
                                  ? null
                                  : digit == 'erase'
                                  ? onErase
                                  : () => onDigit(digit),
                              child: digit == 'erase'
                                  ? const Icon(
                                      Icons.backspace_outlined,
                                      semanticLabel: 'Hapus digit',
                                    )
                                  : Text(
                                      digit,
                                      style: const TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                            ),
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: busy ? null : onSubmit,
            child: busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppTheme.primary,
                    ),
                  )
                : Text(actionLabel),
          ),
        ),
        if (footer != null) ...[const SizedBox(height: 12), footer!],
      ],
    ),
  );
}
