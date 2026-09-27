import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../auth/data/models/user_model.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_utils.dart';

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});
  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  List<UserModel> _users = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    debugPrint('🖥️ [USER_MANAGEMENT] initState');
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadUsers());
  }

  Future<void> _loadUsers() async {
    final auth = context.read<AuthProvider>();
    final users = await auth.getUsers();
    if (!mounted) return;
    setState(() { _users = users; _loading = false; });
  }

  void _showUserDialog({UserModel? user}) {
    final nameCtrl = TextEditingController(text: user?.name ?? '');
    final pinCtrl = TextEditingController();
    String role = user?.role ?? 'kasir';
    bool isActive = user?.isActive ?? true;

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(user == null ? 'Tambah Pengguna' : 'Edit Pengguna'),
          content: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Nama'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: pinCtrl,
                  decoration: InputDecoration(
                    labelText: user == null ? 'PIN (4-6 digit) *' : 'PIN Baru (kosong = tidak ubah)',
                    prefixIcon: const Icon(Icons.lock_outline),
                  ),
                  keyboardType: TextInputType.number,
                  obscureText: true,
                  maxLength: 6,
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: role,
                  decoration: const InputDecoration(labelText: 'Peran'),
                  items: const [
                    DropdownMenuItem(value: 'admin', child: Text('👑 Admin')),
                    DropdownMenuItem(value: 'manajer', child: Text('👔 Manajer')),
                    DropdownMenuItem(value: 'kasir', child: Text('🧑‍💼 Kasir')),
                  ],
                  onChanged: (v) => setS(() => role = v!),
                ),
                if (user != null) ...[
                  const SizedBox(height: 8),
                  SwitchListTile(
                    title: const Text('Aktif'),
                    value: isActive,
                    activeColor: AppTheme.primaryRed,
                    onChanged: (v) => setS(() => isActive = v),
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryRed),
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty) return;
                if (user == null && pinCtrl.text.isEmpty) return;
                final auth = context.read<AuthProvider>();
                bool ok;
                if (user == null) {
                  ok = await auth.addUser(nameCtrl.text.trim(), pinCtrl.text, role);
                } else {
                  ok = await auth.updateUser(
                    user.authId ?? '', nameCtrl.text.trim(),
                    pinCtrl.text.isEmpty ? '' : pinCtrl.text,
                    role,
                  );
                }
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                  if (ok) { _loadUsers(); }
                }
              },
              child: Text(user == null ? 'Tambah' : 'Simpan', style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppTheme.primaryRed,
        title: const Text('Manajemen Pengguna'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
                physics: const ClampingScrollPhysics(),
              padding: const EdgeInsets.all(12),
              itemCount: _users.length,
              itemBuilder: (context, i) {
                final user = _users[i];
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: (user.role == 'admin' || user.role == 'owner' || user.role == 'superadmin') ? AppTheme.lightOrange : Colors.grey[100],
                      child: Text((user.role == 'admin' || user.role == 'owner' || user.role == 'superadmin') ? '👑' : '🧑‍💼', style: const TextStyle(fontSize: 20)),
                    ),
                    title: Text(user.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: (user.role == 'admin' || user.role == 'owner' || user.role == 'superadmin') ? AppTheme.lightOrange : Colors.grey[100],
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            AppUtils.getRoleLabel(user.role),
                            style: TextStyle(
                              fontSize: 11,
                              color: (user.role == 'admin' || user.role == 'owner' || user.role == 'superadmin') ? AppTheme.primaryRed : Colors.grey[700],
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: user.isActive ? Colors.green[50] : Colors.red[50],
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            user.isActive ? 'Aktif' : 'Nonaktif',
                            style: TextStyle(
                              fontSize: 11,
                              color: user.isActive ? Colors.green[700] : Colors.red,
                            ),
                          ),
                        ),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
          tooltip: 'Edit',
                          icon: const Icon(Icons.edit, color: AppTheme.primaryOrange),
                          onPressed: () => _showUserDialog(user: user),
                        ),
                        if ((user.authId ?? '') != context.read<AuthProvider>().currentUser?.authId)
                          IconButton(
          tooltip: 'Edit',
                            icon: const Icon(Icons.person_off, color: Colors.red),
                            onPressed: () async {
                              await context.read<AuthProvider>().deleteUser(user.authId ?? '');
                              _loadUsers();
                            },
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'features_settings_presentation_screens_user_management_screen_2',
        backgroundColor: AppTheme.primaryRed,
        onPressed: () => _showUserDialog(),
        child: const Icon(Icons.person_add, color: Colors.white),
      ),
    );
  }
}
