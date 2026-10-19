import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../core/theme/app_colors.dart';

/// Scanner de billets (organisateur / admin) : lit UN code QR et renvoie
/// son texte brut à l'écran précédent (Navigator.pop). L'analyse du billet
/// et le pointage se font ensuite (TicketRules.scanVerdict + togglePresent).
///
/// Caméra : la permission est demandée par mobile_scanner. Refusée : on
/// explique, avec un bouton vers les réglages de l'app (utile si elle a été
/// refusée définitivement).
class ScanTicketScreen extends StatefulWidget {
  const ScanTicketScreen({super.key});

  @override
  State<ScanTicketScreen> createState() => _ScanTicketScreenState();
}

class _ScanTicketScreenState extends State<ScanTicketScreen> {
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return; // un seul résultat
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw != null && raw.isNotEmpty) {
        _done = true;
        Navigator.pop(context, raw);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Fermer le scanner',
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Scanner un billet'),
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => _CameraError(error: error),
          ),
          // Cadre de visée et consigne.
          IgnorePointer(
            child: Center(
              child: Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white, width: 3),
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 32,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
              child: const Text(
                'Placez le code QR du billet dans le cadre.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Caméra indisponible : permission refusée (avec accès aux réglages) ou autre erreur.
class _CameraError extends StatelessWidget {
  final MobileScannerException error;
  const _CameraError({required this.error});

  @override
  Widget build(BuildContext context) {
    final denied = error.errorCode == MobileScannerErrorCode.permissionDenied;
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(24),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(denied ? Icons.no_photography_outlined : Icons.error_outline_rounded,
              size: 40, color: AppColors.textSecondary),
          const SizedBox(height: 12),
          Text(
            denied
                ? "Accès à la caméra refusé. Autorisez la caméra dans les réglages de l'app pour scanner les billets."
                : 'Caméra indisponible pour le moment.',
            textAlign: TextAlign.center,
          ),
          if (denied) ...[
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(44, 48)),
              // Ouvre la page de l'app dans les réglages (même si refus définitif).
              onPressed: Geolocator.openAppSettings,
              child: const Text('Ouvrir les réglages'),
            ),
          ],
        ],
      ),
    );
  }
}
