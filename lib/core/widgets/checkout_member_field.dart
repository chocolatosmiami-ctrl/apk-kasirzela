import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/checkout_member.dart';
import '../theme/app_theme.dart';

class CheckoutMemberField extends StatelessWidget {
  final CheckoutMemberController controller;
  final bool enabled;
  const CheckoutMemberField(
      {super.key, required this.controller, this.enabled = true});

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final member = controller.selected;
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: AppTheme.onAction,
                border: Border.all(color: AppTheme.borderLight),
                borderRadius: BorderRadius.circular(12)),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Kode member (opsional)',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              if (member == null) ...[
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                      child: TextField(
                    controller: controller.input,
                    enabled: enabled && !controller.busy,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6)
                    ],
                    decoration:
                        const InputDecoration(hintText: '6 digit kode member'),
                    onSubmitted: (_) {
                      if (enabled) controller.verify();
                    },
                  )),
                  const SizedBox(width: 8),
                  FilledButton(
                      onPressed: !enabled || controller.busy
                          ? null
                          : controller.verify,
                      style: FilledButton.styleFrom(
                          minimumSize: const Size(64, 48)),
                      child: controller.busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Cek')),
                ]),
                if (controller.error != null) ...[
                  const SizedBox(height: 8),
                  Text(controller.error!,
                      style: const TextStyle(
                          color: AppTheme.danger, fontSize: 13)),
                ],
                if (controller.input.text.isNotEmpty)
                  TextButton(
                      onPressed:
                          enabled && !controller.busy ? controller.clear : null,
                      child: const Text('Lanjut tanpa member')),
              ] else ...[
                Row(children: [
                  const Icon(Icons.check_circle_outline,
                      color: AppTheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(member.name,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        Text(
                            'Kode ${member.number}${member.points == null ? '' : ' · ${member.points} poin'}',
                            style: const TextStyle(
                                color: AppTheme.textSecondary, fontSize: 13)),
                      ])),
                  TextButton(
                      onPressed: enabled ? controller.clear : null,
                      child: const Text('Hapus')),
                ]),
                const SizedBox(height: 6),
                const Text(
                    'Poin transaksi diperbarui setelah sinkronisasi berhasil.',
                    style:
                        TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
              ],
            ]),
          );
        },
      );
}
