import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/layout.dart';
import '../../core/theme/app_tokens.dart';
import '../../models/user_model.dart';
import '../../providers/admin_users_provider.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/filter_chip_pill.dart';
import '../../widgets/initials_avatar.dart';
import '../../widgets/pill_button.dart';
import '../../widgets/skeleton_box.dart';
import '../../widgets/status_chip.dart';
import 'admin_card_review_screen.dart';

String roleLabel(UserRole role) => switch (role) {
      UserRole.student => 'Étudiant',
      UserRole.recruiter => 'Recruteur',
      UserRole.admin => 'Admin',
    };

/// Administration : liste des comptes avec recherche, filtres, changement de
/// rôle, désactivation et accès à la validation des cartes étudiant.
class AdminUsersScreen extends StatefulWidget {
  final StudentCardStatus? initialCardFilter;

  const AdminUsersScreen({super.key, this.initialCardFilter});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    final filter = widget.initialCardFilter;
    if (filter != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.read<AdminUsersProvider>().setCardFilter(filter);
      });
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _openSheet(AppUser user) {
    final provider = context.read<AdminUsersProvider>();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ChangeNotifierProvider<AdminUsersProvider>.value(
        value: provider,
        child: _UserSheet(user: user),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AdminUsersProvider>();
    final t = AppTokens.of(context);
    final users = provider.filtered;

    Widget body;
    if (provider.isLoading) {
      body = ListView.builder(
        padding: const EdgeInsets.fromLTRB(kPagePadding, 8, kPagePadding, 24),
        itemCount: 6,
        itemBuilder: (_, __) => const Padding(
          padding: EdgeInsets.symmetric(vertical: 6),
          child: SkeletonBox(height: 64),
        ),
      );
    } else if (provider.error != null && provider.users.isEmpty) {
      body = ListView(children: [
        EmptyState(
            icon: Icons.error_outline_rounded,
            title: 'Chargement impossible',
            subtitle: provider.error!),
      ]);
    } else if (users.isEmpty) {
      body = ListView(children: const [
        EmptyState(
          icon: Icons.group_off_rounded,
          title: 'Aucun utilisateur',
          subtitle: 'Aucun compte ne correspond à ta recherche.',
        ),
      ]);
    } else {
      body = ListView.builder(
        padding: const EdgeInsets.fromLTRB(kPagePadding, 4, kPagePadding, 24),
        itemCount: users.length,
        itemBuilder: (_, i) =>
            _UserRow(user: users[i], onTap: () => _openSheet(users[i])),
      );
    }

    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(title: const Text('Utilisateurs')),
      body: Column(
        children: [
          Padding(
            padding:
                const EdgeInsets.fromLTRB(kPagePadding, 8, kPagePadding, 4),
            child: _SearchField(
              focus: _focus,
              onChanged: provider.setQuery,
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: kPagePadding),
            child: Row(
              children: [
                for (final role in const [
                  (UserRole.student, 'Étudiants'),
                  (UserRole.recruiter, 'Recruteurs'),
                  (UserRole.admin, 'Admins'),
                ]) ...[
                  FilterChipPill(
                    label: role.$2,
                    selected: provider.roleFilter == role.$1,
                    onTap: () => provider.setRoleFilter(
                        provider.roleFilter == role.$1 ? null : role.$1),
                  ),
                  const SizedBox(width: 8),
                ],
                FilterChipPill(
                  label: 'En attente',
                  icon: Icons.hourglass_top_rounded,
                  selected: provider.cardFilter == StudentCardStatus.pending,
                  onTap: () => provider.setCardFilter(
                      provider.cardFilter == StudentCardStatus.pending
                          ? null
                          : StudentCardStatus.pending),
                ),
              ],
            ),
          ),
          Expanded(child: body),
        ],
      ),
    );
  }
}

/// Champ de recherche au style de [SearchPill] ; un tap sur la pastille
/// donne le focus au champ.
class _SearchField extends StatelessWidget {
  final FocusNode focus;
  final ValueChanged<String> onChanged;

  const _SearchField({required this.focus, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: focus.requestFocus,
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(26),
          border: dark ? Border.all(color: t.outline) : null,
          boxShadow: dark ? null : t.cardShadow,
        ),
        child: Row(
          children: [
            Icon(Icons.search_rounded, size: 22, color: t.textSecondary),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                focusNode: focus,
                onChanged: onChanged,
                textInputAction: TextInputAction.search,
                style: Theme.of(context).textTheme.bodyLarge,
                decoration: InputDecoration(
                  hintText: 'Rechercher un nom ou un email',
                  hintStyle: Theme.of(context).textTheme.bodyMedium,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  isDense: true,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

({StatusChipStyle style, String label})? _cardChip(AppUser u) {
  if (u.isVerifiedStudent ||
      u.studentCard.status == StudentCardStatus.verified) {
    return (style: StatusChipStyle.success, label: 'Vérifié');
  }
  return switch (u.studentCard.status) {
    StudentCardStatus.pending => (
        style: StatusChipStyle.warning,
        label: 'En attente'
      ),
    StudentCardStatus.rejected => (
        style: StatusChipStyle.danger,
        label: 'Carte refusée'
      ),
    _ => null,
  };
}

class _UserRow extends StatelessWidget {
  final AppUser user;
  final VoidCallback onTap;

  const _UserRow({required this.user, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final card = _cardChip(user);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                InitialsAvatar(
                    initials: user.initials, photoUrl: user.photoUrl, size: 42),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user.fullName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.titleSmall),
                      Text(user.email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.labelMedium),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          StatusChip(
                              label: roleLabel(user.role),
                              style: StatusChipStyle.neutral),
                          if (card != null)
                            StatusChip(label: card.label, style: card.style),
                          if (user.disabled)
                            const StatusChip(
                                label: 'Désactivé',
                                style: StatusChipStyle.danger),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UserSheet extends StatefulWidget {
  final AppUser user;

  const _UserSheet({required this.user});

  @override
  State<_UserSheet> createState() => _UserSheetState();
}

class _UserSheetState extends State<_UserSheet> {
  late UserRole _role = widget.user.role;
  bool _busy = false;

  bool get _hasCard {
    final card = widget.user.studentCard;
    return card.status == StudentCardStatus.pending ||
        ((card.status == StudentCardStatus.rejected ||
                card.status == StudentCardStatus.verified) &&
            card.imagePath != null);
  }

  Future<void> _run(
      Future<bool> Function(AdminUsersProvider) action, String done) async {
    final provider = context.read<AdminUsersProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _busy = true);
    final ok = await action(provider);
    if (!mounted) return;
    setState(() => _busy = false);
    messenger.showSnackBar(SnackBar(
        content: Text(ok ? done : (provider.error ?? 'Action impossible.'))));
    if (ok) navigator.pop();
  }

  void _openCard() {
    final provider = context.read<AdminUsersProvider>();
    final navigator = Navigator.of(context);
    navigator.pop();
    navigator.push(MaterialPageRoute<void>(
      builder: (_) => ChangeNotifierProvider<AdminUsersProvider>.value(
        value: provider,
        child: AdminCardReviewScreen(user: widget.user),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AdminUsersProvider>();
    final text = Theme.of(context).textTheme;
    final user = widget.user;
    final canConfirm =
        _role != user.role && provider.canChangeRole(user, _role);

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(kPagePadding, 0, kPagePadding,
            16 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: AppTokens.of(context).handle,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Text(user.fullName, style: text.titleLarge),
            Text(user.email, style: text.labelMedium),
            const SizedBox(height: 16),
            Text('Changer le rôle', style: text.titleSmall),
            RadioGroup<UserRole>(
              groupValue: _role,
              onChanged: (v) {
                if (!_busy) setState(() => _role = v ?? _role);
              },
              child: Column(
                children: [
                  for (final role in UserRole.values)
                    RadioListTile<UserRole>(
                      contentPadding: EdgeInsets.zero,
                      title: Text(roleLabel(role)),
                      value: role,
                    ),
                ],
              ),
            ),
            if (_role != user.role && !provider.canChangeRole(user, _role))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                    'Le dernier administrateur ne peut pas changer son propre rôle.',
                    style: text.labelMedium),
              ),
            PillButton(
              label: 'Confirmer',
              isLoading: _busy,
              onPressed: canConfirm
                  ? () =>
                      _run((p) => p.changeRole(user, _role), 'Rôle mis à jour')
                  : null,
            ),
            const SizedBox(height: 12),
            PillButton(
              label: user.disabled
                  ? 'Réactiver le compte'
                  : 'Désactiver le compte',
              style: user.disabled ? PillStyle.ghost : PillStyle.danger,
              onPressed: _busy
                  ? null
                  : () => _run((p) => p.setDisabled(user, !user.disabled),
                      user.disabled ? 'Compte réactivé' : 'Compte désactivé'),
            ),
            if (_hasCard) ...[
              const SizedBox(height: 12),
              PillButton(
                label: 'Voir la carte',
                style: PillStyle.ghost,
                icon: Icons.badge_rounded,
                onPressed: _busy ? null : _openCard,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
