import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../models/event_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/event_provider.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/status_badge.dart';

/// Détail d'un événement — inscription + fonctionnalités avancées :
/// synchronisation calendrier natif et aperçu du lieu.
class EventDetailScreen extends StatelessWidget {
  final EventModel event;
  const EventDetailScreen({super.key, required this.event});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final isGuest = auth.status != AuthStatus.authenticated;
    final isOwner = auth.currentUser?.id == event.organizerId;
    final isRegistered = auth.currentUser != null && event.isUserRegistered(auth.currentUser!.id);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Événement'),
        actions: [
          if (isOwner)
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () async {
                await context.read<EventProvider>().deleteEvent(event.id);
                if (context.mounted) Navigator.pop(context);
              },
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 110),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 140,
              decoration: BoxDecoration(
                gradient: AppColors.heroGradient,
                borderRadius: BorderRadius.circular(18),
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.celebration_outlined, size: 48, color: Colors.white),
            ),
            const SizedBox(height: 16),
            StatusBadge.info(event.category.toUpperCase()),
            const SizedBox(height: 10),
            Text(event.title, style: Theme.of(context).textTheme.displayMedium),
            const SizedBox(height: 10),
            _InfoRow(icon: Icons.calendar_today_outlined,
                text: DateFormat('EEEE d MMMM yyyy à HH:mm', 'fr_FR').format(event.startDate)),
            const SizedBox(height: 6),
            _InfoRow(icon: Icons.place_outlined, text: event.location),
            const SizedBox(height: 6),
            _InfoRow(icon: Icons.people_alt_outlined,
                text: '${event.registeredUserIds.length} inscrit(s) · Organisé par ${event.organizerName}'),
            const SizedBox(height: 18),
            Text('Description', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(event.description, style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.6)),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: () async {
                final link = context.read<EventProvider>().buildCalendarLink(event);
                await Clipboard.setData(ClipboardData(text: link));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Lien Google Calendar copié — collez-le dans votre navigateur.'),
                    ),
                  );
                }
              },
              icon: const Icon(Icons.event_available_outlined, size: 18),
              label: const Text('Ajouter à mon calendrier'),
            ),
            const SizedBox(height: 12),
            if (!isGuest)
              PrimaryButton(
                label: isRegistered ? "Annuler l'inscription" : "S'inscrire à l'événement",
                icon: isRegistered ? Icons.close_rounded : Icons.check_circle_outline_rounded,
                gradient: isRegistered ? AppColors.accentGradient : AppColors.primaryGradient,
                onPressed: () =>
                    context.read<EventProvider>().toggleRegistration(event, auth.currentUser!.id),
              )
            else
              Text('Connectez-vous pour vous inscrire à cet événement.',
                  style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: AppColors.textSecondary),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
      ],
    );
  }
}
