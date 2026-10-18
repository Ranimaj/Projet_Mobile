import 'package:flutter/material.dart';
import '../home/home_screen.dart';
import '../profile/profile_screen.dart';
import '../vente_don/vente_don_list_screen.dart';
import '../annonces/annonces_list_screen.dart';
import '../evenements/evenements_list_screen.dart';
import '../stages_emploi/stages_list_screen.dart';

/// Coquille de navigation principale — les 6 onglets (Accueil + 5 gestions)
/// correspondent exactement à la barre de navigation des maquettes.
class AppShell extends StatefulWidget {
  final int initialIndex;
  const AppShell({super.key, this.initialIndex = 0});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late int _index = widget.initialIndex;

  void _select(int i) {
    if (i != _index) setState(() => _index = i);
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      HomeScreen(onNavigate: _select),
      const VenteDonListScreen(),
      const AnnoncesListScreen(),
      const EvenementsListScreen(),
      const StagesListScreen(),
      const ProfileScreen(),
    ];
    return Scaffold(
      body: IndexedStack(index: _index, children: screens),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: _select,
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.home_rounded), label: 'Accueil'),
          BottomNavigationBarItem(
              icon: Icon(Icons.storefront_rounded), label: 'Vente/Don'),
          BottomNavigationBarItem(
              icon: Icon(Icons.campaign_rounded), label: 'Annonces'),
          BottomNavigationBarItem(
              icon: Icon(Icons.event_rounded), label: 'Événements'),
          BottomNavigationBarItem(
              icon: Icon(Icons.work_rounded), label: 'Stages'),
          BottomNavigationBarItem(
              icon: Icon(Icons.person_rounded), label: 'Profil'),
        ],
      ),
    );
  }
}
