import '../../../../core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../data/models/table_model.dart';
import '../providers/table_provider.dart';

class TableEditorDialog extends StatefulWidget {
  final TableModel? table;
  const TableEditorDialog({super.key, this.table});
  @override
  State<TableEditorDialog> createState() => _TableEditorDialogState();
}

class _TableEditorDialogState extends State<TableEditorDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name, _zone, _capacity;
  bool _saving = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.table?.name ?? '');
    _zone = TextEditingController(text: widget.table?.zone ?? 'Dalam');
    _capacity = TextEditingController(text: '${widget.table?.capacity ?? 4}');
  }
  @override
  void dispose() {
    _name.dispose(); _zone.dispose(); _capacity.dispose();
    super.dispose();
  }
  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() { _saving = true; _error = null; });
    final provider = context.read<TableProvider>();
    final ok = await provider.saveTable(existing: widget.table,
      name: _name.text, zone: _zone.text, capacity: int.parse(_capacity.text));
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, true);
    } else {
      setState(() { _saving = false; _error = provider.lastError ?? 'Gagal menyimpan meja.'; });
    }
  }
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      title: Text(widget.table == null ? 'Tambah meja' : 'Edit meja'),
      content: SizedBox(width: 420, child: SingleChildScrollView(
        child: Form(key: _form, child: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextFormField(controller: _name, enabled: !_saving, autofocus: true,
              maxLength: 80, textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Nama meja', hintText: 'Contoh: Teras A'),
              validator: (v) => v == null || v.trim().isEmpty ? 'Isi nama meja.' : null),
            const SizedBox(height: 8),
            TextFormField(controller: _zone, enabled: !_saving, maxLength: 40,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Area', hintText: 'Dalam, Luar, VIP'),
              validator: (v) => v == null || v.trim().isEmpty ? 'Isi area meja.' : null),
            const SizedBox(height: 8),
            TextFormField(controller: _capacity, enabled: !_saving,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly], maxLength: 3,
              decoration: const InputDecoration(labelText: 'Jumlah kursi'),
              validator: (v) {
                final n = int.tryParse(v ?? '');
                return n == null || n < 1 || n > 100 ? 'Isi 1–100 kursi.' : null;
              }),
            const SizedBox(height: 8),
            const Text('Disimpan ke server untuk cabang yang sedang dipilih.',
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 12),
              child: Text(_error!, style: const TextStyle(color: AppTheme.danger))),
          ])),
      )),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Batal')),
        FilledButton(onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Menyimpan…' : 'Simpan')),
      ],
    ),
  );
}
