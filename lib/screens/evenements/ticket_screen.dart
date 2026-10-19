import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../core/theme/app_colors.dart';
import '../../models/event_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/event_provider.dart';
import 'event_rules.dart';
import 'event_style.dart';
import 'ticket_rules.dart';

/// « Mon billet » : lit l'événement à jour dans le provider (alimenté en
/// direct par la fiche) et l'étudiant connecté. Fonctionne hors-ligne avec
/// les données en cache.
class TicketScreen extends StatelessWidget {
  final EventModel event;
  const TicketScreen({super.key, required this.event});

  @override
  Widget build(BuildContext context) {
    final current = context.watch<EventProvider>().findById(event.id) ?? event;
    final user = context.watch<AuthProvider>().currentUser;
    return Scaffold(
      appBar: AppBar(title: const Text('Mon billet')),
      body: user == null
          ? const Center(child: Text('Connectez-vous pour voir votre billet.'))
          : TicketView(event: current, uid: user.id, studentName: user.fullName),
    );
  }
}

/// Contenu du billet : QR code à montrer à l'entrée, infos de l'événement,
/// nom de l'étudiant, état du paiement et de la présence.
///
/// Widget sans Provider : il reçoit l'événement et le nom, donc il est
/// testable facilement (voir ticket_screen_test.dart).
class TicketView extends StatelessWidget {
  final EventModel event;
  final String uid;
  final String studentName;
  const TicketView({super.key, required this.event, required this.uid, required this.studentName});

  @override
  Widget build(BuildContext context) {
    final cancelled = event.status == EventStatus.cancelled;
    final color = EventStyle.categoryColor(event.category);
    final payment = TicketRules.payment(event, uid);
    final present = TicketRules.isPresent(event, uid);
    final date = DateFormat('EEEE d MMMM yyyy', 'fr_FR').format(event.startDate);
    final time =
        '${DateFormat('HH:mm', 'fr_FR').format(event.startDate)} → ${DateFormat('HH:mm', 'fr_FR').format(event.endDate)}';

    final qr = QrImageView(
      data: TicketRules.buildTicketPayload(event.id, uid),
      size: 200,
      backgroundColor: Colors.white,
      semanticsLabel: 'Code QR du billet de $studentName pour ${event.title}',
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                color: cancelled ? AppColors.textSecondary : color,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Text(
                  cancelled ? 'BILLET ANNULÉ' : 'BILLET · ${event.category.toUpperCase()}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w800, letterSpacing: 1.2, fontSize: 12),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Annulé : QR grisé et barré d'un tampon « ANNULÉ ».
                    cancelled
                        ? Opacity(
                            opacity: 0.25,
                            child: ColorFiltered(
                              colorFilter: const ColorFilter.mode(Colors.grey, BlendMode.saturation),
                              child: qr,
                            ),
                          )
                        : qr,
                    if (cancelled)
                      Transform.rotate(
                        angle: -0.3,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            border: Border.all(color: AppColors.danger, width: 3),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text('ANNULÉ',
                              style: TextStyle(color: AppColors.danger, fontSize: 26, fontWeight: FontWeight.w900)),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(studentName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                    const SizedBox(height: 4),
                    Text(event.title,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 12),
                    _Line(icon: Icons.calendar_today_outlined, text: '${date[0].toUpperCase()}${date.substring(1)}'),
                    _Line(icon: Icons.schedule_rounded, text: time),
                    _Line(icon: Icons.place_outlined, text: event.location),
                    _Line(icon: Icons.sell_outlined, text: EventRules.priceLabel(event)),
                    const SizedBox(height: 12),
                    // Wrap : les puces passent à la ligne en grand texte.
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (cancelled)
                          const _Chip(text: 'Annulé', color: AppColors.danger)
                        else ...[
                          _Chip(
                            text: TicketRules.paymentLabel(payment),
                            color: payment == TicketPayment.toPay ? AppColors.warning : AppColors.success,
                          ),
                          if (present) const _Chip(text: 'Présent ✓', color: AppColors.success),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text(
          cancelled ? "Cet événement a été annulé : ce billet n'est plus valable." : "Montrez ce code à l'entrée.",
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }
}

class _Line extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Line({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 16, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ]),
      );
}

class _Chip extends StatelessWidget {
  final String text;
  final Color color;
  const _Chip({required this.text, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color),
        ),
        child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w700)),
      );
}
