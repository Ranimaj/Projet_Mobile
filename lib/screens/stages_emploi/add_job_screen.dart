import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/job_offer_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/job_provider.dart';
import '../../widgets/primary_button.dart';

/// BF10 — publication d'une offre de stage/emploi par un recruteur.
class AddJobScreen extends StatefulWidget {
  const AddJobScreen({super.key});

  @override
  State<AddJobScreen> createState() => _AddJobScreenState();
}

class _AddJobScreenState extends State<AddJobScreen> {
  final _formKey = GlobalKey<FormState>();
  final _companyCtrl = TextEditingController();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _skillsCtrl = TextEditingController();
  JobType _type = JobType.stage;
  bool _submitting = false;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    final auth = context.read<AuthProvider>();

    final skills = _skillsCtrl.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

    final draft = JobOfferModel(
      id: '',
      recruiterId: auth.currentUser!.id,
      companyName: _companyCtrl.text.trim(),
      title: _titleCtrl.text.trim(),
      description: _descCtrl.text.trim(),
      type: _type,
      location: _locationCtrl.text.trim(),
      requiredSkills: skills,
      postedAt: DateTime.now(),
    );
    await context.read<JobProvider>().createOffer(draft);

    if (!mounted) return;
    setState(() => _submitting = false);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Offre publiée !')));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Publier une offre')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<JobType>(
                segments: const [
                  ButtonSegment(value: JobType.stage, label: Text('Stage')),
                  ButtonSegment(value: JobType.emploi, label: Text('Emploi')),
                ],
                selected: {_type},
                onSelectionChanged: (s) => setState(() => _type = s.first),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _companyCtrl,
                decoration: const InputDecoration(labelText: "Nom de l'entreprise"),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Champ requis' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _titleCtrl,
                decoration: const InputDecoration(labelText: 'Titre du poste'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Champ requis' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _locationCtrl,
                decoration: const InputDecoration(labelText: 'Lieu'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Champ requis' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _descCtrl,
                maxLines: 5,
                decoration: const InputDecoration(labelText: 'Description du poste'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Champ requis' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _skillsCtrl,
                decoration: const InputDecoration(
                  labelText: 'Compétences requises (séparées par des virgules)',
                  hintText: 'Flutter, Firebase, Figma',
                ),
              ),
              const SizedBox(height: 20),
              PrimaryButton(label: "Publier l'offre", isLoading: _submitting, onPressed: _submit),
            ],
          ),
        ),
      ),
    );
  }
}
