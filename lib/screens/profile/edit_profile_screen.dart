import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../widgets/primary_button.dart';

/// BF3 — modifier son profil (nom, filière, année, bio).
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _majorCtrl;
  late final TextEditingController _yearCtrl;

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthProvider>().currentUser!;
    _nameCtrl = TextEditingController(text: user.fullName);
    _majorCtrl = TextEditingController(text: user.major ?? '');
    _yearCtrl = TextEditingController(text: user.year ?? '');
  }

  Future<void> _save() async {
    final auth = context.read<AuthProvider>();
    final updated = auth.currentUser!.copyWith(
      fullName: _nameCtrl.text.trim(),
      major: _majorCtrl.text.trim(),
      year: _yearCtrl.text.trim(),
    );
    final ok = await auth.updateProfile(updated);
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profil mis à jour')));
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('Modifier le profil')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Nom complet')),
            const SizedBox(height: 14),
            TextField(controller: _majorCtrl, decoration: const InputDecoration(labelText: 'Filière')),
            const SizedBox(height: 14),
            TextField(controller: _yearCtrl, decoration: const InputDecoration(labelText: "Année d'étude")),
            const SizedBox(height: 24),
            PrimaryButton(label: 'Enregistrer', isLoading: auth.isLoading, onPressed: _save),
          ],
        ),
      ),
    );
  }
}
