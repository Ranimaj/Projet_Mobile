import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../models/job_offer_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/job_provider.dart';
import '../../widgets/primary_button.dart';

/// BF11 — postuler à une offre : upload du CV + lettre de motivation.
/// Fonctionne hors-ligne : la candidature est mise en file et envoyée au
/// retour du réseau.
class ApplyScreen extends StatefulWidget {
  final JobOfferModel offer;
  const ApplyScreen({super.key, required this.offer});

  @override
  State<ApplyScreen> createState() => _ApplyScreenState();
}

class _ApplyScreenState extends State<ApplyScreen> {
  final _coverCtrl = TextEditingController();
  File? _cvFile;
  String? _cvName;
  bool _submitting = false;

  Future<void> _pickCv() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf', 'doc', 'docx']);
    if (result != null && result.files.single.path != null) {
      setState(() {
        _cvFile = File(result.files.single.path!);
        _cvName = result.files.single.name;
      });
    }
  }

  Future<void> _submit() async {
    final auth = context.read<AuthProvider>();
    setState(() => _submitting = true);
    await context.read<JobProvider>().applyToOffer(
          offer: widget.offer,
          candidateId: auth.currentUser!.id,
          cvFile: _cvFile,
          coverLetter: _coverCtrl.text.trim().isEmpty ? null : _coverCtrl.text.trim(),
        );
    if (!mounted) return;
    setState(() => _submitting = false);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Candidature envoyée !')));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Postuler')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.offer.title, style: Theme.of(context).textTheme.titleMedium),
            Text(widget.offer.companyName, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: _pickCv,
              icon: const Icon(Icons.upload_file_outlined, size: 18),
              label: Text(_cvName ?? 'Joindre mon CV (PDF/DOC)'),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _coverCtrl,
              maxLines: 6,
              decoration: const InputDecoration(labelText: 'Lettre de motivation (optionnel)'),
            ),
            const SizedBox(height: 10),
            if (_cvFile == null)
              Text(
                'Vous pouvez postuler sans réseau — la candidature sera envoyée dès la reconnexion.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
              ),
            const SizedBox(height: 20),
            PrimaryButton(label: 'Envoyer ma candidature', isLoading: _submitting, onPressed: _submit),
          ],
        ),
      ),
    );
  }
}
