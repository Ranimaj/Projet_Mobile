import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_tokens.dart';
import '../../models/user_model.dart';
import '../../providers/admin_users_provider.dart';
import '../../widgets/hero_sheet_scaffold.dart';
import '../../widgets/pill_button.dart';
import '../../widgets/round_icon_button.dart';
import '../../widgets/setting_row.dart';
import '../../widgets/status_chip.dart';

/// Validation d'une carte étudiant : photo (zoomable), identité déclarée,
/// puis « Valider » ou « Refuser » (motif obligatoire).
class AdminCardReviewScreen extends StatefulWidget {
  final AppUser user;

  const AdminCardReviewScreen({super.key, required this.user});

  @override
  State<AdminCardReviewScreen> createState() => _AdminCardReviewScreenState();
}

class _AdminCardReviewScreenState extends State<AdminCardReviewScreen> {
  Future<String>? _imageUrl;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final path = widget.user.studentCard.imagePath;
    if (path != null) {
      _imageUrl = context.read<AdminUsersProvider>().cardImageUrl(path);
    }
  }

  static String _date(DateTime? d) =>
      d == null ? '—' : DateFormat('d MMMM y', 'fr_FR').format(d);

  Future<void> _decide({required bool approve, String? reason}) async {
    final provider = context.read<AdminUsersProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _busy = true);
    final ok = await provider.reviewCard(widget.user,
        approve: approve, reason: reason);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      messenger.showSnackBar(
          SnackBar(content: Text(approve ? 'Carte validée' : 'Carte refusée')));
      navigator.pop();
    } else {
      messenger.showSnackBar(
          SnackBar(content: Text(provider.error ?? 'Action impossible.')));
    }
  }

  Future<void> _reject() async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const _RejectDialog(),
    );
    if (reason != null) await _decide(approve: false, reason: reason);
  }

  void _zoom(String url) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog.fullscreen(
        backgroundColor: AppTokens.of(ctx).background,
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                maxScale: 5,
                child: CachedNetworkImage(imageUrl: url, fit: BoxFit.contain),
              ),
            ),
            Positioned(
              top: MediaQuery.of(ctx).padding.top + 8,
              left: 12,
              child: RoundIconButton(
                icon: Icons.close_rounded,
                tooltip: 'Fermer',
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _hero(AppTokens t) {
    Widget box(IconData icon, String label) => Container(
          color: t.primarySoft,
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 40, color: t.onPrimarySoft),
              const SizedBox(height: 8),
              Text(label, style: Theme.of(context).textTheme.labelMedium),
            ],
          ),
        );
    final future = _imageUrl;
    if (future == null) {
      return box(Icons.image_not_supported_rounded, 'Aucune image');
    }
    return FutureBuilder<String>(
      future: future,
      builder: (context, snap) {
        if (snap.hasError) {
          return box(Icons.broken_image_rounded, 'Image indisponible');
        }
        final url = snap.data;
        if (url == null) return Container(color: t.primarySoft);
        return GestureDetector(
          onTap: () => _zoom(url),
          child: CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.cover,
            placeholder: (_, __) => Container(color: t.primarySoft),
            errorWidget: (_, __, ___) =>
                box(Icons.broken_image_rounded, 'Image indisponible'),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final text = Theme.of(context).textTheme;
    final user = widget.user;
    final card = user.studentCard;
    final verified = card.status == StudentCardStatus.verified;

    final (chipStyle, chipLabel) = switch (card.status) {
      StudentCardStatus.verified => (StatusChipStyle.success, 'Carte validée'),
      StudentCardStatus.rejected => (StatusChipStyle.danger, 'Carte refusée'),
      StudentCardStatus.pending => (
          StatusChipStyle.warning,
          'En attente de validation'
        ),
      StudentCardStatus.none => (StatusChipStyle.neutral, 'Aucune carte'),
    };

    return HeroSheetScaffold(
      hero: _hero(t),
      heroLeading: RoundIconButton(
        icon: Icons.arrow_back_rounded,
        tooltip: 'Retour',
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      bottomBar: verified
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text('Validée le ${_date(card.reviewedAt)}',
                  textAlign: TextAlign.center, style: text.titleSmall),
            )
          : Row(
              children: [
                Expanded(
                  child: PillButton(
                    label: 'Refuser',
                    style: PillStyle.danger,
                    onPressed: _busy ? null : _reject,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: PillButton(
                    label: 'Valider',
                    isLoading: _busy,
                    onPressed: _busy ? null : () => _decide(approve: true),
                  ),
                ),
              ],
            ),
      children: [
        Align(
            alignment: Alignment.centerLeft,
            child: StatusChip(label: chipLabel, style: chipStyle)),
        const SizedBox(height: 12),
        Text(user.fullName, style: text.headlineMedium),
        const SizedBox(height: 16),
        SettingGroup(
          children: [
            SettingRow(
                icon: Icons.school_rounded,
                title: user.major ?? '—',
                subtitle: 'Filière'),
            SettingRow(
                icon: Icons.stairs_rounded,
                title: user.year ?? '—',
                subtitle: 'Année'),
            SettingRow(
                icon: Icons.mail_rounded, title: user.email, subtitle: 'Email'),
            SettingRow(
                icon: Icons.badge_rounded,
                title: user.studentId ?? '—',
                subtitle: 'Identifiant saisi'),
            SettingRow(
                icon: Icons.event_rounded,
                title: _date(card.submittedAt),
                subtitle: 'Envoyée le'),
            if (card.status == StudentCardStatus.rejected &&
                card.rejectReason != null)
              SettingRow(
                  icon: Icons.report_rounded,
                  title: card.rejectReason!,
                  subtitle: 'Motif du refus'),
          ],
        ),
      ],
    );
  }
}

class _RejectDialog extends StatefulWidget {
  const _RejectDialog();

  @override
  State<_RejectDialog> createState() => _RejectDialogState();
}

class _RejectDialogState extends State<_RejectDialog> {
  final _form = GlobalKey<FormState>();
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  void _submit() {
    if (_form.currentState!.validate()) {
      Navigator.of(context).pop(_reason.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Refuser la carte'),
      content: Form(
        key: _form,
        child: TextFormField(
          controller: _reason,
          autofocus: true,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Motif du refus'),
          validator: (v) => (v ?? '').trim().length < 5
              ? 'Motif requis (5 caractères minimum)'
              : null,
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Annuler')),
        TextButton(onPressed: _submit, child: const Text('Refuser')),
      ],
    );
  }
}
