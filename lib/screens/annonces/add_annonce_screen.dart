import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_constants.dart';
import '../../models/annonce_model.dart';
import '../../providers/annonce_provider.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/primary_button.dart';

/// BF7 — publier une annonce campus. Si "Officielle", elle est épinglée
/// automatiquement en tête de fil (fonctionnalité avancée).
class AddAnnonceScreen extends StatefulWidget {
  const AddAnnonceScreen({super.key});

  @override
  State<AddAnnonceScreen> createState() => _AddAnnonceScreenState();
}

class _AddAnnonceScreenState extends State<AddAnnonceScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _contentCtrl = TextEditingController();
  String _category = AppConstants.annonceCategories.first;
  bool _isUrgent = false;
  bool _submitting = false;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    final auth = context.read<AuthProvider>();

    final draft = AnnonceModel(
      id: '',
      authorId: auth.currentUser!.id,
      authorName: auth.currentUser!.fullName,
      title: _titleCtrl.text.trim(),
      content: _contentCtrl.text.trim(),
      category: _category,
      isUrgent: _isUrgent,
      createdAt: DateTime.now(),
    );
    await context.read<AnnonceProvider>().createAnnonce(draft);

    if (!mounted) return;
    setState(() => _submitting = false);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Annonce publiée !')));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = context.watch<AuthProvider>().currentUser?.role.name == 'admin';

    return Scaffold(
      appBar: AppBar(title: const Text('Publier une annonce')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _titleCtrl,
                decoration: const InputDecoration(labelText: 'Titre'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Titre requis' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _contentCtrl,
                maxLines: 5,
                decoration: const InputDecoration(labelText: 'Contenu'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Contenu requis' : null,
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: _category,
                decoration: const InputDecoration(labelText: 'Catégorie'),
                items: AppConstants.annonceCategories
                    .where((c) => c != 'Officielle' || isAdmin) // seul l'admin publie "Officielle"
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (v) => setState(() => _category = v!),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Annonce urgente (notification push)', style: TextStyle(fontSize: 13.5)),
                value: _isUrgent,
                onChanged: (v) => setState(() => _isUrgent = v),
              ),
              const SizedBox(height: 20),
              PrimaryButton(label: 'Publier', isLoading: _submitting, onPressed: _submit),
            ],
          ),
        ),
      ),
    );
  }
}
