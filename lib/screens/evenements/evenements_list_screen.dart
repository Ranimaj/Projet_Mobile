import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../providers/event_provider.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/offline_banner.dart';
import 'add_event_screen.dart';
import 'event_detail_screen.dart';

/// BF8/BF9 — liste des événements à venir, filtrable par catégorie,
/// avec sélecteur de date rapide (bande horizontale des 14 prochains jours).
class EvenementsListScreen extends StatefulWidget {
  const EvenementsListScreen({super.key});

  @override
  State<EvenementsListScreen> createState() => _EvenementsListScreenState();
}

class _EvenementsListScreenState extends State<EvenementsListScreen> {
  DateTime? _selectedDay;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => context.read<EventProvider>().load());
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<EventProvider>();
    final isGuest = context.watch<AuthProvider>().status != AuthStatus.authenticated;
    final today = DateTime.now();

    final events = _selectedDay == null ? provider.upcoming : provider.eventsOnDay(_selectedDay!);

    return Scaffold(
      appBar: AppBar(title: const Text('Événements')),
      floatingActionButton: isGuest
          ? null
          : FloatingActionButton(
              onPressed: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const AddEventScreen())),
              child: const Icon(Icons.add_rounded),
            ),
      body: SafeArea(
        child: Column(
          children: [
            const OfflineBanner(),
            SizedBox(
              height: 72,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                itemCount: 14,
                itemBuilder: (context, i) {
                  final day = DateTime(today.year, today.month, today.day + i);
                  final selected = _selectedDay != null &&
                      _selectedDay!.year == day.year &&
                      _selectedDay!.month == day.month &&
                      _selectedDay!.day == day.day;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedDay = selected ? null : day),
                    child: Container(
                      width: 52,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        gradient: selected ? AppColors.primaryGradient : null,
                        color: selected ? null : Colors.white,
                        border: Border.all(color: selected ? AppColors.primary : AppColors.border),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(DateFormat('E', 'fr_FR').format(day).toUpperCase(),
                              style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                  color: selected ? Colors.white70 : AppColors.textSecondary)),
                          const SizedBox(height: 2),
                          Text('${day.day}',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: selected ? Colors.white : AppColors.textPrimary)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  _Chip(label: 'Toutes', selected: provider.categoryFilter == null,
                      onTap: () => provider.setCategoryFilter(null)),
                  const SizedBox(width: 8),
                  ...AppConstants.eventCategories.map((c) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _Chip(
                          label: c,
                          selected: provider.categoryFilter == c,
                          onTap: () => provider.setCategoryFilter(provider.categoryFilter == c ? null : c),
                        ),
                      )),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: provider.isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : events.isEmpty
                      ? const EmptyState(
                          icon: Icons.event_outlined,
                          title: 'Aucun événement à venir',
                          subtitle: "Changez de date ou créez le premier événement du campus.",
                        )
                      : RefreshIndicator(
                          onRefresh: provider.load,
                          child: ListView.separated(
                            padding: const EdgeInsets.fromLTRB(20, 0, 20, 90),
                            itemCount: events.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 10),
                            itemBuilder: (context, i) {
                              final e = events[i];
                              return GestureDetector(
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(builder: (_) => EventDetailScreen(event: e)),
                                ),
                                child: Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    border: Border.all(color: AppColors.border),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 52,
                                        height: 52,
                                        decoration: BoxDecoration(
                                          gradient: AppColors.accentGradient,
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Text(DateFormat('MMM', 'fr_FR').format(e.startDate).toUpperCase(),
                                                style: const TextStyle(
                                                    color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                                            Text('${e.startDate.day}',
                                                style: const TextStyle(
                                                    color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(e.title,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                                            const SizedBox(height: 4),
                                            Row(children: [
                                              const Icon(Icons.place_outlined, size: 13, color: AppColors.textSecondary),
                                              const SizedBox(width: 3),
                                              Expanded(
                                                child: Text(e.location,
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: Theme.of(context).textTheme.bodyMedium),
                                              ),
                                            ]),
                                          ],
                                        ),
                                      ),
                                      Text('${e.registeredUserIds.length}',
                                          style: const TextStyle(
                                              fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary)),
                                      const SizedBox(width: 3),
                                      const Icon(Icons.people_alt_outlined, size: 15, color: AppColors.primary),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Chip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.white,
          border: Border.all(color: selected ? AppColors.primary : AppColors.border),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: selected ? Colors.white : AppColors.textSecondary)),
      ),
    );
  }
}
