import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/constants/layout.dart';
import '../../core/theme/app_tokens.dart';
import '../../services/stages/stage_services.dart';
import '../auth/auth_feedback.dart';
import '../bottom_action_bar.dart';
import '../empty_state.dart';
import '../round_icon_button.dart';

String formatDate(DateTime d) => DateFormat('d MMM y', 'fr_FR').format(d);
String formatDateTime(DateTime d) => DateFormat("d MMM y 'à' HH:mm", 'fr_FR').format(d);

void showSuccess(BuildContext context, String message) => showAuthSnack(context, message, isError: false);
void showError(BuildContext context, Object error) => showAuthSnack(context, error.toString());

/// Centre le contenu sur les grands écrans ; pleine largeur sur téléphone.
class ContentWidth extends StatelessWidget {
  const ContentWidth({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: kContentMaxWidth),
          child: child,
        ),
      );
}

/// Écran d'onglet : grand titre, actions à droite, contenu défilant.
class TabPage extends StatelessWidget {
  const TabPage({super.key, required this.title, this.subtitle, this.actions = const [], required this.children});

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ContentWidth(
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(kPagePadding, 12, kPagePadding, 24),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: text.displaySmall),
                        if (subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(subtitle!, style: text.bodyMedium),
                        ],
                      ],
                    ),
                  ),
                  ...actions,
                ],
              ),
              const SizedBox(height: 16),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

/// Écran poussé : barre de titre, contenu défilant, barre d'actions facultative.
class DetailPage extends StatelessWidget {
  const DetailPage({super.key, required this.title, this.actions = const [], required this.children, this.bottom});

  final String title;
  final List<Widget> actions;
  final List<Widget> children;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: actions,
      ),
      body: SafeArea(
        top: false,
        bottom: bottom == null,
        child: Column(
          children: [
            Expanded(
              child: ContentWidth(
                child: ListView(
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(kPagePadding, 8, kPagePadding, 24),
                  children: children,
                ),
              ),
            ),
            if (bottom != null) BottomActionBar(child: ContentWidth(child: bottom!)),
          ],
        ),
      ),
    );
  }
}

class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.onTap, this.padding = const EdgeInsets.all(16)});

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final radius = BorderRadius.circular(20);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: kCardGap),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: radius,
        border: dark ? Border.all(color: t.outline) : null,
        boxShadow: t.cardShadow,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: kHeaderGap),
        child: Row(
          children: [
            Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
            if (trailing != null) trailing!,
          ],
        ),
      );
}

/// Bouton rond d'ajout placé dans l'en-tête des listes.
class AddButton extends StatelessWidget {
  const AddButton({super.key, required this.tooltip, required this.onPressed});

  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => RoundIconButton(
        icon: Icons.add_rounded,
        tooltip: tooltip,
        size: 44,
        style: RoundButtonStyle.primary,
        onPressed: onPressed,
      );
}

/// Champ de recherche réel, en forme de pilule.
class SearchField extends StatelessWidget {
  const SearchField({super.key, required this.hint, required this.onChanged});

  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => TextField(
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(hintText: hint, prefixIcon: const Icon(Icons.search_rounded, size: 22)),
      );
}

/// Rangée de filtres défilant horizontalement, sans déborder sur petit écran.
class FilterRow extends StatelessWidget {
  const FilterRow({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final child in children) Padding(padding: const EdgeInsets.only(right: 8), child: child),
          ],
        ),
      );
}

Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
}) async {
  final t = AppTokens.of(context);
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: TextButton.styleFrom(foregroundColor: t.danger),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Feuille modale dont le contenu remonte au-dessus du clavier.
Future<T?> showFormSheet<T>(BuildContext context, {required WidgetBuilder builder}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppTokens.of(context).surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(kPagePadding, 20, kPagePadding, 20),
        child: SafeArea(top: false, child: ContentWidth(child: builder(ctx))),
      ),
    ),
  );
}

/// Charge des données depuis SQLite et les relit après chaque écriture.
class DbBuilder<T> extends StatefulWidget {
  const DbBuilder({super.key, required this.load, required this.builder, this.fullScreen = false});

  final Future<T> Function(StageServices services) load;
  final Widget Function(BuildContext context, T data) builder;

  /// À activer quand le builder occupe toute la route : l'attente garde un fond.
  final bool fullScreen;

  @override
  State<DbBuilder<T>> createState() => _DbBuilderState<T>();
}

class _DbBuilderState<T> extends State<DbBuilder<T>> {
  late final StageServices _services = context.read<StageServices>();
  (T,)? _data;
  Object? _error;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _services.changes.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    _services.changes.removeListener(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    final generation = ++_generation;
    try {
      final data = await widget.load(_services);
      if (mounted && generation == _generation) {
        setState(() {
          _data = (data,);
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && generation == _generation) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    if (data != null) return widget.builder(context, data.$1);
    final Widget placeholder = _error != null
        ? const EmptyState(
            icon: Icons.error_outline_rounded,
            title: 'Chargement impossible',
            subtitle: 'Fermez puis rouvrez cet écran pour réessayer.',
          )
        : const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(child: CircularProgressIndicator()),
          );
    return widget.fullScreen ? Scaffold(appBar: AppBar(), body: placeholder) : placeholder;
  }
}
