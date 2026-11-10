import 'dart:math' as math;

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
import 'ticket_link.dart';
import 'ticket_rules.dart';

/// « Mon billet » : lit l'événement à jour dans le provider (alimenté en
/// direct par la fiche) et l'étudiant connecté. Fonctionne hors-ligne : les
/// données sont sur le téléphone.
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

  /// Fond de la carte : blanc dans les deux thèmes (le QR reste sombre sur
  /// clair). Toutes les couleurs de texte de la carte en sont déduites,
  /// jamais du thème ambiant.
  static const Color cardColor = Colors.white;

  /// Référence lisible du billet, tirée des identifiants du QR
  /// (« Billet n° 3B70-3DA7 »), la même que le paramètre « r » de la page
  /// web du billet. Affichage seulement : jamais stockée ni utilisée pour
  /// valider un billet.
  static String reference(String eventId, String uid) => 'Billet n° ${TicketLink.referenceCode(eventId, uid)}';

  @override
  Widget build(BuildContext context) {
    final cancelled = event.status == EventStatus.cancelled;
    final color = EventStyle.categoryColor(event.category);
    final payment = TicketRules.payment(event, uid);
    final present = TicketRules.isPresent(event, uid);
    final date = DateFormat('EEEE d MMMM yyyy', 'fr_FR').format(event.startDate);
    final time =
        '${DateFormat('HH:mm', 'fr_FR').format(event.startDate)} → ${DateFormat('HH:mm', 'fr_FR').format(event.endDate)}';

    final ink = TicketColors.ink(cardColor);
    final inkSoft = TicketColors.inkSoft(cardColor);

    // Adresse de la page web du billet : l'appareil photo d'un téléphone
    // l'ouvre, le scanner de l'organisateur n'en lit que « CC1|… ».
    // Correction d'erreur basse : QR moins dense, lu sur écran sans dégât.
    final qr = QrImageView(
      data: TicketLink.build(event, uid, studentName),
      errorCorrectionLevel: QrErrorCorrectLevel.L,
      size: 200,
      backgroundColor: Colors.white,
      semanticsLabel: 'Code QR du billet de $studentName pour ${event.title}',
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        Container(
          key: const Key('ticket-card'),
          decoration: BoxDecoration(
            color: cardColor,
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
                          child: Text('ANNULÉ',
                              style: TextStyle(
                                  color: TicketColors.readableOn(AppColors.danger, cardColor),
                                  fontSize: 26,
                                  fontWeight: FontWeight.w900)),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                reference(event.id, uid),
                key: const Key('ticket-reference'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: inkSoft,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.1,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(studentName,
                        key: const Key('ticket-attendee'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: inkSoft)),
                    const SizedBox(height: 4),
                    Text(event.title,
                        key: const Key('ticket-title'),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 22, height: 1.25, fontWeight: FontWeight.w800, color: ink)),
                    const SizedBox(height: 12),
                    _Line(
                        icon: Icons.calendar_today_outlined,
                        text: '${date[0].toUpperCase()}${date.substring(1)}',
                        ink: ink,
                        iconColor: inkSoft),
                    _Line(icon: Icons.schedule_rounded, text: time, ink: ink, iconColor: inkSoft),
                    _Line(icon: Icons.place_outlined, text: event.location, ink: ink, iconColor: inkSoft),
                    // Gratuit : la puce le dit déjà, pas de ligne en double.
                    if (payment != TicketPayment.free)
                      _Line(icon: Icons.sell_outlined, text: EventRules.priceLabel(event), ink: ink, iconColor: inkSoft),
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

/// Couleurs lisibles sur la carte du billet (contraste WCAG ≥ 4,5:1).
class TicketColors {
  TicketColors._();

  static const double minContrast = 4.5;

  /// Rapport de contraste WCAG entre deux couleurs opaques.
  static double contrast(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
  }

  /// [color] assombri (fond clair) ou éclairci (fond foncé) juste assez pour
  /// atteindre [minContrast] sur [background].
  static Color readableOn(Color color, Color background) {
    final toward = background.computeLuminance() > 0.5 ? Colors.black : Colors.white;
    var c = color;
    for (var t = 0.05; contrast(c, background) < minContrast && t <= 1.0; t += 0.05) {
      c = Color.lerp(color, toward, t)!;
    }
    return c;
  }

  /// Texte principal : encre sombre sur fond clair, blanche sur fond foncé.
  static Color ink(Color background) =>
      readableOn(background.computeLuminance() > 0.5 ? AppColors.textPrimary : Colors.white, background);

  /// Texte secondaire (nom, référence, icônes).
  static Color inkSoft(Color background) => readableOn(
      background.computeLuminance() > 0.5 ? AppColors.textSecondary : const Color(0xFFD1D5DB), background);
}

class _Line extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color ink;
  final Color iconColor;
  const _Line({required this.icon, required this.text, required this.ink, required this.iconColor});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 16, color: iconColor),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(fontSize: 15, color: ink))),
        ]),
      );
}

class _Chip extends StatelessWidget {
  final String text;
  final Color color;
  const _Chip({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    final tint = color.withValues(alpha: 0.12);
    // Texte lisible sur la teinte de la puce, posée sur la carte.
    final background = Color.alphaBlend(tint, TicketView.cardColor);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color),
      ),
      child: Text(text,
          style: TextStyle(color: TicketColors.readableOn(color, background), fontWeight: FontWeight.w700)),
    );
  }
}
