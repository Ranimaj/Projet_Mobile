import 'package:flutter/material.dart';
import '../../core/constants/layout.dart';
import '../../widgets/floating_nav_bar.dart';
import '../home/home_screen.dart';
import '../vente_don/vente_don_list_screen.dart';
import '../annonces/annonces_list_screen.dart';
import '../evenements/evenements_list_screen.dart';
import '../stages_emploi/stages_list_screen.dart';

/// Coquille de navigation principale : cinq onglets sous une barre flottante.
/// Le profil n'est plus un onglet, il s'ouvre depuis l'avatar de l'accueil.
class AppShell extends StatefulWidget {
  final int initialIndex;
  const AppShell({super.key, this.initialIndex = 0});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late int _index = widget.initialIndex;

  static const _items = [
    FloatingNavItem(icon: Icons.home_rounded, label: 'Accueil'),
    FloatingNavItem(icon: Icons.sell_rounded, label: 'Marché'),
    FloatingNavItem(icon: Icons.campaign_rounded, label: 'Annonces'),
    FloatingNavItem(icon: Icons.event_rounded, label: 'Événements'),
    FloatingNavItem(icon: Icons.work_rounded, label: 'Stages'),
  ];

  void _select(int i) {
    if (i != _index) setState(() => _index = i);
  }

  /// Laisse de la place à la barre flottante sans toucher aux écrans de module.
  /// Clavier ouvert : la barre est masquée, la marge aussi.
  Widget _clearBar(Widget screen, {required bool keyboard}) =>
      MediaQuery.removePadding(
        context: context,
        removeBottom: true,
        child: Padding(
          padding: EdgeInsets.only(
              bottom: keyboard
                  ? 0
                  : kFloatingNavInset + MediaQuery.viewPaddingOf(context).bottom),
          child: screen,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final screens = [
      HomeScreen(onNavigate: _select),
      const VenteDonListScreen(),
      const AnnoncesListScreen(),
      const EvenementsListScreen(),
      const StagesListScreen(),
    ];
    // A docked keyboard shrinks the body: the bar would ride on top of it.
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Scaffold(
      extendBody: true,
      body: Stack(
        children: [
          IndexedStack(
            index: _index,
            children: [
              for (final s in screens) _clearBar(s, keyboard: keyboard)
            ],
          ),
          if (!keyboard)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: FloatingNavBar(
                  index: _index, onChanged: _select, items: _items),
            ),
        ],
      ),
    );
  }
}
