import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../services/report_service.dart';
import 'auth/auth_feedback.dart';

/// Ouvre le formulaire « Signaler [targetName] ». Renvoie `true` si le
/// signalement est parti.
Future<bool> showReportUserSheet(
  BuildContext context, {
  required String targetId,
  required String targetName,
  String? articleId,
  ReportService? service,
}) async {
  final sent = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => ChangeNotifierProvider.value(
      value: context.read<AuthProvider>(),
      child: _ReportSheet(targetId: targetId, targetName: targetName, articleId: articleId, service: service),
    ),
  );
  return sent == true;
}

class _ReportSheet extends StatefulWidget {
  final String targetId;
  final String targetName;
  final String? articleId;
  final ReportService? service;
  const _ReportSheet({required this.targetId, required this.targetName, this.articleId, this.service});

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  ReportReason? _reason;
  final _details = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final me = context.read<AuthProvider>().currentUser;
    final reason = _reason;
    if (me == null || reason == null || _sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final service = widget.service ?? ReportService(FirebaseFirestore.instance);
      await service.submit(
        reporterId: me.id,
        reporterName: me.fullName,
        targetId: widget.targetId,
        targetName: widget.targetName,
        reason: reason,
        details: _details.text,
        articleId: widget.articleId,
      );
      if (!mounted) return;
      showAuthSnack(context, 'Merci, un admin va examiner ton signalement.', isError: false);
      Navigator.pop(context, true);
    } on AlreadyReported {
      setState(() => _error = 'Tu as déjà signalé ce compte. Un admin s\'en occupe.');
    } catch (_) {
      setState(() => _error = 'Envoi impossible pour le moment. Réessaie.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Signaler ${widget.targetName}', style: text.titleLarge),
              const SizedBox(height: 4),
              Text('Ton signalement reste anonyme pour la personne concernée.', style: text.bodyMedium),
              const SizedBox(height: 12),
              RadioGroup<ReportReason>(
                groupValue: _reason,
                onChanged: (r) => setState(() => _reason = r),
                child: Column(
                  children: [
                    for (final r in ReportReason.values)
                      RadioListTile<ReportReason>(
                        key: Key('report-reason-${r.name}'),
                        value: r,
                        contentPadding: EdgeInsets.zero,
                        title: Text(r.label),
                      ),
                  ],
                ),
              ),
              TextField(
                key: const Key('report-details'),
                controller: _details,
                maxLines: 3,
                maxLength: ReportService.maxDetails,
                decoration: const InputDecoration(hintText: 'Que s\'est-il passé ? (facultatif)'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: text.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.error)),
              ],
              const SizedBox(height: 12),
              FilledButton(
                key: const Key('report-send'),
                onPressed: _reason == null || _sending ? null : _send,
                child: Text(_sending ? 'Envoi…' : 'Envoyer le signalement'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
