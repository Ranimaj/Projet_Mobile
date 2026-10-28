import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_tokens.dart';
import '../../providers/theme_provider.dart';
import '../../widgets/charts/area_line_chart.dart';
import '../../widgets/charts/chart_models.dart';
import '../../widgets/charts/donut_chart.dart';
import '../../widgets/charts/h_bar_chart.dart';
import '../../widgets/featured_card.dart';
import '../../widgets/filter_chip_pill.dart';
import '../../widgets/floating_nav_bar.dart';
import '../../widgets/initials_avatar.dart';
import '../../widgets/photo_card.dart';
import '../../widgets/pill_button.dart';
import '../../widgets/round_icon_button.dart';
import '../../widgets/search_pill.dart';
import '../../widgets/setting_row.dart';
import '../../widgets/skeleton_box.dart';
import '../../widgets/stat_tile.dart';
import '../../widgets/status_chip.dart';
import '../../widgets/sync_chip.dart';

/// Debug-only page listing every token, text style and component in the
/// current theme. Open it only under `if (kDebugMode)`.
class DesignGalleryScreen extends StatelessWidget {
  const DesignGalleryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Galerie du design')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          _ThemeModeSwitch(),
          _Section('Couleurs', _Swatches()),
          _Section('Styles de texte', _TextStyles()),
          _Section('Boutons pilule', _PillButtons()),
          _Section('Boutons ronds', _RoundButtons()),
          _Section('Pastilles de statut', _StatusChips()),
          _Section('Filtres', _Filters()),
          _Section('Statistiques', _Stats()),
          _Section('Avatars', _Avatars()),
          _Section('Squelette', SkeletonBox(width: double.infinity, height: 16)),
          _Section('Cartes', _Cards()),
          _Section('Recherche et synchro', _SearchAndSync()),
          _Section('Réglages', _Settings()),
          _Section('Barre de navigation', _NavPreview()),
          _Section('Graphiques', _Charts()),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title, this.child);
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            child,
          ],
        ),
      );
}

class _ThemeModeSwitch extends StatelessWidget {
  const _ThemeModeSwitch();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ThemeProvider>();
    return SegmentedButton<ThemeMode>(
      segments: const [
        ButtonSegment(value: ThemeMode.light, label: Text('Clair')),
        ButtonSegment(value: ThemeMode.dark, label: Text('Sombre')),
        ButtonSegment(value: ThemeMode.system, label: Text('Système')),
      ],
      selected: {provider.mode},
      onSelectionChanged: (s) => provider.setMode(s.first),
    );
  }
}

class _Swatches extends StatelessWidget {
  const _Swatches();

  static String _hex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final text = Theme.of(context).textTheme;
    final colors = <String, Color>{
      'primary': t.primary,
      'primarySoft': t.primarySoft,
      'onPrimarySoft': t.onPrimarySoft,
      'background': t.background,
      'surface': t.surface,
      'surfaceMuted': t.surfaceMuted,
      'outline': t.outline,
      'textPrimary': t.textPrimary,
      'textSecondary': t.textSecondary,
      'success': t.success,
      'successSoft': t.successSoft,
      'warning': t.warning,
      'warningSoft': t.warningSoft,
      'danger': t.danger,
      'dangerSoft': t.dangerSoft,
      'handle': t.handle,
    };
    return Column(
      children: [
        for (final e in colors.entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: e.value,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: t.outline),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(e.key, style: text.bodyMedium)),
                Text(_hex(e.value), style: text.labelMedium),
              ],
            ),
          ),
      ],
    );
  }
}

class _TextStyles extends StatelessWidget {
  const _TextStyles();

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final styles = <String, TextStyle?>{
      'displayLarge': tt.displayLarge,
      'displayMedium': tt.displayMedium,
      'displaySmall': tt.displaySmall,
      'headlineLarge': tt.headlineLarge,
      'headlineMedium': tt.headlineMedium,
      'headlineSmall': tt.headlineSmall,
      'titleLarge': tt.titleLarge,
      'titleMedium': tt.titleMedium,
      'titleSmall': tt.titleSmall,
      'bodyLarge': tt.bodyLarge,
      'bodyMedium': tt.bodyMedium,
      'labelLarge': tt.labelLarge,
      'labelMedium': tt.labelMedium,
      'labelSmall': tt.labelSmall,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final e in styles.entries)
          if (e.value != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(e.key, style: e.value),
            ),
      ],
    );
  }
}

class _Wrap extends StatelessWidget {
  const _Wrap(this.children);
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: children);
}

class _PillButtons extends StatelessWidget {
  const _PillButtons();

  @override
  Widget build(BuildContext context) => Column(
        children: [
          for (final s in PillStyle.values)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: PillButton(label: s.name, style: s, onPressed: () {}),
            ),
        ],
      );
}

class _RoundButtons extends StatelessWidget {
  const _RoundButtons();

  @override
  Widget build(BuildContext context) => _Wrap([
        for (final s in RoundButtonStyle.values)
          RoundIconButton(icon: Icons.favorite_border, style: s, tooltip: s.name, onPressed: () {}),
        RoundIconButton(icon: Icons.notifications_none, tooltip: 'avec point', showDot: true, onPressed: () {}),
      ]);
}

class _StatusChips extends StatelessWidget {
  const _StatusChips();

  @override
  Widget build(BuildContext context) => _Wrap([
        for (final s in StatusChipStyle.values) StatusChip(label: s.name, style: s),
      ]);
}

class _Filters extends StatelessWidget {
  const _Filters();

  @override
  Widget build(BuildContext context) => const _Wrap([
        FilterChipPill(label: 'Actif', selected: true),
        FilterChipPill(label: 'Inactif', selected: false),
      ]);
}

class _Stats extends StatelessWidget {
  const _Stats();

  @override
  Widget build(BuildContext context) => const Row(
        children: [
          Expanded(child: StatTile(value: '128', label: 'Annonces')),
          SizedBox(width: 12),
          Expanded(child: StatTile(value: '4,8', label: 'Note')),
        ],
      );
}

class _Avatars extends StatelessWidget {
  const _Avatars();

  @override
  Widget build(BuildContext context) => const _Wrap([
        InitialsAvatar(initials: 'AB'),
        InitialsAvatar(initials: 'CD', verified: true),
        InitialsAvatar(initials: 'EF', size: 64, verified: true),
      ]);
}

class _Cards extends StatelessWidget {
  const _Cards();

  @override
  Widget build(BuildContext context) => const Column(
        children: [
          PhotoCard(
            title: 'Vélo de ville',
            placeholderIcon: Icons.pedal_bike,
            chip: StatusChip(label: 'Disponible', style: StatusChipStyle.success),
            showHeart: true,
          ),
          SizedBox(height: 12),
          FeaturedCard(
            chipLabel: 'À la une',
            title: 'Soirée d’intégration',
            meta: [FeaturedMeta(Icons.event, 'Vendredi'), FeaturedMeta(Icons.place_outlined, 'Campus')],
            actionLabel: 'Voir',
          ),
        ],
      );
}

class _SearchAndSync extends StatelessWidget {
  const _SearchAndSync();

  @override
  Widget build(BuildContext context) => const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SearchPill(hint: 'Rechercher'),
          SizedBox(height: 12),
          _Wrap([
            SyncChip(online: true, pending: 0),
            SyncChip(online: true, pending: 3),
            SyncChip(online: false, pending: 0),
          ]),
        ],
      );
}

class _Settings extends StatelessWidget {
  const _Settings();

  @override
  Widget build(BuildContext context) => SettingGroup(
        title: 'Compte',
        children: [
          SettingRow(icon: Icons.person_outline, title: 'Profil', subtitle: 'Nom et photo', onTap: () {}),
          SettingRow(icon: Icons.logout, title: 'Déconnexion', destructive: true, onTap: () {}),
        ],
      );
}

class _NavPreview extends StatefulWidget {
  const _NavPreview();

  @override
  State<_NavPreview> createState() => _NavPreviewState();
}

class _NavPreviewState extends State<_NavPreview> {
  int _index = 0;

  @override
  Widget build(BuildContext context) => FloatingNavBar(
        index: _index,
        onChanged: (i) => setState(() => _index = i),
        items: const [
          FloatingNavItem(icon: Icons.home_rounded, label: 'Accueil'),
          FloatingNavItem(icon: Icons.storefront_outlined, label: 'Annonces'),
          FloatingNavItem(icon: Icons.person_outline, label: 'Profil'),
        ],
      );
}

class _Charts extends StatelessWidget {
  const _Charts();

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AreaLineChart(points: [
          ChartPoint(label: 'Lun', value: 4),
          ChartPoint(label: 'Mar', value: 9),
          ChartPoint(label: 'Mer', value: 6),
          ChartPoint(label: 'Jeu', value: 12),
          ChartPoint(label: 'Ven', value: 8),
          ChartPoint(label: 'Sam', value: 15),
        ]),
        const SizedBox(height: 16),
        DonutChart(
          centerLabel: '100',
          slices: [
            ChartSlice(label: 'Vente', value: 55, color: t.primary),
            ChartSlice(label: 'Don', value: 30, color: t.success),
            ChartSlice(label: 'Autre', value: 15, color: t.warning),
          ],
        ),
        const SizedBox(height: 16),
        HBarChart(
          bars: [
            ChartBar(label: 'Annonces', value: 42, color: t.primary),
            ChartBar(label: 'Stages', value: 25, color: t.success),
            ChartBar(label: 'Événements', value: 10, color: t.warning),
          ],
        ),
      ],
    );
  }
}
