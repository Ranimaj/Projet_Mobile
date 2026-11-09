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
  /// Choix de l'utilisateur ; null tant qu'il n'a rien choisi.
  String? _category;
  bool _isUrgent = false;
  bool _submitting = false;

  /// Seul un admin publie une annonce « Officielle ».
  static List<String> _categoriesFor(bool isAdmin) =>
      [for (final c in AppConstants.annonceCategories) if (c != 'Officielle' || isAdmin) c];

  /// La catégorie retenue, toujours parmi celles que l'utilisateur peut choisir.
  String _selectedCategory(bool isAdmin) {
    final allowed = _categoriesFor(isAdmin);
    final chosen = _category;
    return chosen != null && allowed.contains(chosen) ? chosen : allowed.first;
  }

  static bool _isAdmin(AuthProvider auth) => auth.currentUser?.role.name == 'admin';

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
      category: _selectedCategory(_isAdmin(auth)),
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
    final isAdmin = _isAdmin(context.watch<AuthProvider>());

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
                // La clé suit le rôle : si les catégories proposées changent,
                // le champ repart sur une valeur qui existe dans la liste.
                key: ValueKey(isAdmin),
                initialValue: _selectedCategory(isAdmin),
                decoration: const InputDecoration(labelText: 'Catégorie'),
                items: [
                  for (final c in _categoriesFor(isAdmin)) DropdownMenuItem(value: c, child: Text(c)),
                ],
                onChanged: (v) => setState(() => _category = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Annonce urgente', style: TextStyle(fontSize: 13.5)),
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
