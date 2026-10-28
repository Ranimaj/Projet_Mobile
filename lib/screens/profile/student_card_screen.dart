import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_tokens.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/connectivity_provider.dart';
import '../../widgets/auth/auth_feedback.dart';
import '../../widgets/bottom_action_bar.dart';
import '../../widgets/hero_sheet_scaffold.dart';
import '../../widgets/pill_button.dart';
import '../../widgets/round_icon_button.dart';
import '../../widgets/status_chip.dart';

/// Envoi de la carte étudiant pour validation (photo galerie ou appareil).
class StudentCardScreen extends StatefulWidget {
  /// Sélecteur injectable (tests).
  final ImagePicker? picker;

  const StudentCardScreen({super.key, this.picker});

  @override
  State<StudentCardScreen> createState() => _StudentCardScreenState();
}

class _StudentCardScreenState extends State<StudentCardScreen> {
  late final ImagePicker _picker = widget.picker ?? ImagePicker();
  File? _photo;

  Future<void> _pick(ImageSource source) async {
    final picked = await _picker.pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 1600,
    );
    if (picked == null || !mounted) return;
    setState(() => _photo = File(picked.path));
  }

  Future<void> _submit() async {
    final photo = _photo;
    if (photo == null) return;
    final auth = context.read<AuthProvider>();
    final online = context.read<ConnectivityProvider>().isOnline;
    final ok = await auth.submitStudentCard(photo, isOnline: online);
    if (!mounted) return;
    if (ok) {
      showAuthSnack(
        context,
        online
            ? 'Carte envoyée, en attente de validation'
            : 'Carte enregistrée, envoi à la reconnexion',
        isError: false,
      );
      Navigator.of(context).pop();
    } else {
      showAuthSnack(context, auth.errorMessage ?? 'Envoi impossible. Réessaie.');
    }
  }

  ({StatusChipStyle style, String label, IconData icon})? _status(
      AppUser user, bool queued) {
    final card = user.studentCard;
    if (user.isVerifiedStudent || card.status == StudentCardStatus.verified) {
      return (
        style: StatusChipStyle.success,
        label: 'Étudiant vérifié',
        icon: Icons.verified_rounded
      );
    }
    return switch (card.status) {
      StudentCardStatus.pending when queued => (
          style: StatusChipStyle.neutral,
          label: 'En attente de connexion',
          icon: Icons.cloud_off_rounded
        ),
      StudentCardStatus.pending => (
          style: StatusChipStyle.warning,
          label: 'En cours de validation',
          icon: Icons.hourglass_top_rounded
        ),
      StudentCardStatus.rejected => (
          style: StatusChipStyle.danger,
          label: 'Carte refusée',
          icon: Icons.error_outline_rounded
        ),
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final t = AppTokens.of(context);
    final text = Theme.of(context).textTheme;
    final status = _status(user, auth.pendingCardQueued);
    final card = user.studentCard;
    final rejected = card.status == StudentCardStatus.rejected;
    final verified = user.isVerifiedStudent || card.status == StudentCardStatus.verified;
    final busy = auth.isLoading;

    return HeroSheetScaffold(
      hero: ColoredBox(
        color: t.primarySoft,
        child: _photo != null
            ? Image.file(
                _photo!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _placeholder(t),
              )
            : _placeholder(t),
      ),
      heroLeading: RoundIconButton(
        icon: Icons.arrow_back_rounded,
        tooltip: 'Retour',
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      bottomBar: verified
          ? null
          : BottomActionBar(
              child: PillButton(
                label: rejected ? 'Renvoyer' : 'Envoyer pour validation',
                isLoading: busy,
                onPressed: _photo == null ? null : _submit,
              ),
            ),
      children: [
        Text('Carte étudiant', style: text.headlineSmall),
        const SizedBox(height: 8),
        Text(
          'Envoie une photo lisible de ta carte étudiant. Un administrateur la '
          'vérifie, puis ton profil affiche « Étudiant vérifié ».',
          style: text.bodyMedium!.copyWith(color: t.textSecondary),
        ),
        if (status != null) ...[
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: StatusChip(
                label: status.label, style: status.style, icon: status.icon),
          ),
        ],
        if (rejected) ...[
          const SizedBox(height: 8),
          Text(
            card.rejectReason?.isNotEmpty == true
                ? 'Motif : ${card.rejectReason}'
                : 'Ta carte a été refusée. Envoie-la à nouveau.',
            style: text.bodyMedium!.copyWith(color: t.danger),
          ),
        ],
        if (!verified) ...[
          const SizedBox(height: 20),
          PillButton(
            label: 'Galerie',
            icon: Icons.photo_library_rounded,
            style: PillStyle.ghost,
            onPressed: busy ? null : () => _pick(ImageSource.gallery),
          ),
          const SizedBox(height: 12),
          PillButton(
            label: 'Appareil photo',
            icon: Icons.photo_camera_rounded,
            style: PillStyle.ghost,
            onPressed: busy ? null : () => _pick(ImageSource.camera),
          ),
        ],
      ],
    );
  }

  Widget _placeholder(AppTokens t) => Center(
        child: Icon(Icons.badge_rounded, size: 72, color: t.primary),
      );
}
