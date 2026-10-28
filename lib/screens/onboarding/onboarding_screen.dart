import 'package:flutter/material.dart';

import '../../core/constants/layout.dart';
import '../../core/theme/app_tokens.dart';
import '../../services/app_prefs.dart';
import '../../widgets/pill_button.dart';
import '../../widgets/round_icon_button.dart';

const _assets = [
  'assets/images/onboarding/campus_1.jpg',
  'assets/images/onboarding/campus_2.jpg',
  'assets/images/onboarding/campus_3.jpg',
];

const double _sheetRadius = 28.0;
const double _bubbleRadius = 22.0;
const double _bubbleDot = 26.0;

class _PageCopy {
  final String lead;
  final String accent;
  final String subtitle;
  const _PageCopy(this.lead, this.accent, this.subtitle);
}

const _copy = [
  _PageCopy('Toute la vie du campus, ', 'au même endroit',
      'Marché, annonces, événements et stages. Même sans connexion.'),
  _PageCopy('Vends, donne, ', 'trouve',
      'Objets, livres et services entre étudiants, autour de toi.'),
  _PageCopy('Ne rate ', 'rien',
      'Annonces officielles, événements et offres de stage en un seul fil.'),
];

/// Onboarding en trois pages, affiché une seule fois avant l'accueil visiteur.
/// « Commencer » et le lien de connexion marquent l'onboarding comme vu puis
/// appellent [onStart] / [onLogin].
class OnboardingScreen extends StatefulWidget {
  final AppPrefs prefs;
  final VoidCallback? onStart;
  final VoidCallback? onLogin;

  const OnboardingScreen({
    super.key,
    required this.prefs,
    this.onStart,
    this.onLogin,
  });

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _page = 0;
  bool _busy = false;

  Future<void> _finish(VoidCallback? next) async {
    if (_busy) return;
    _busy = true;
    try {
      await widget.prefs.setOnboardingSeen();
    } catch (_) {
      _busy = false;
      rethrow;
    }
    next?.call();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final c = _copy[_page];

    return Scaffold(
      backgroundColor: t.background,
      body: Column(
        children: [
          Expanded(
            child: PageView(
              onPageChanged: (i) => setState(() => _page = i),
              children: const [
                _CollagePage(),
                _PhotoPage(asset: 1),
                _PhotoPage(asset: 2),
              ],
            ),
          ),
          Flexible(
            flex: 2,
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: t.surface,
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(_sheetRadius)),
              ),
              child: SafeArea(
                top: false,
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                        kPagePadding, 12, kPagePadding, 8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: t.handle,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(height: 16),
                        _Title(copy: c),
                        const SizedBox(height: 8),
                        Text(
                          c.subtitle,
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: t.textSecondary),
                        ),
                        const SizedBox(height: 16),
                        _Dots(count: _copy.length, active: _page),
                        const SizedBox(height: 16),
                        PillButton(
                          label: 'Commencer',
                          onPressed: () => _finish(widget.onStart),
                        ),
                        TextButton(
                          style: TextButton.styleFrom(
                            minimumSize: const Size(48, 48),
                            foregroundColor: t.textSecondary,
                          ),
                          onPressed: () => _finish(widget.onLogin),
                          child: Text.rich(
                            TextSpan(
                              text: 'Déjà un compte ? ',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(color: t.textSecondary),
                              children: [
                                TextSpan(
                                  text: 'Se connecter',
                                  style: TextStyle(
                                    color: t.primary,
                                    fontWeight: FontWeight.w700,
                                    decoration: TextDecoration.underline,
                                    decorationColor: t.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Title extends StatelessWidget {
  final _PageCopy copy;
  const _Title({required this.copy});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final style = Theme.of(context)
        .textTheme
        .headlineLarge
        ?.copyWith(fontWeight: FontWeight.w800, color: t.textPrimary);
    return Text.rich(
      TextSpan(
        text: copy.lead,
        style: style,
        children: [
          TextSpan(
            text: copy.accent,
            style: TextStyle(fontStyle: FontStyle.italic, color: t.primary),
          ),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}

class _Dots extends StatelessWidget {
  final int count;
  final int active;
  const _Dots({required this.count, required this.active});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == active ? 18 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: i == active ? t.primary : t.handle,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
      ],
    );
  }
}

/// Photo pleine page avec un dégradé sombre en bas.
class _PhotoPage extends StatelessWidget {
  final int asset;
  const _PhotoPage({required this.asset});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ExcludeSemantics(child: Image.asset(_assets[asset], fit: BoxFit.cover)),
      ],
    );
  }
}

class _OvalSpec {
  /// Centre et diamètre, en fraction de la largeur disponible (y : de la hauteur).
  final double cx, cy, diameter;
  final int asset;
  final Alignment crop;
  const _OvalSpec(this.cx, this.cy, this.diameter, this.asset, this.crop);
}

const _ovals = [
  _OvalSpec(0.22, 0.22, 0.34, 0, Alignment.topLeft),
  _OvalSpec(0.70, 0.16, 0.28, 1, Alignment.center),
  _OvalSpec(0.88, 0.46, 0.22, 2, Alignment.topRight),
  _OvalSpec(0.12, 0.58, 0.24, 1, Alignment.bottomLeft),
  _OvalSpec(0.44, 0.52, 0.36, 2, Alignment.center),
  _OvalSpec(0.76, 0.80, 0.30, 0, Alignment.bottomRight),
];

class _BubbleSpec {
  final double cx, cy, width;
  final IconData icon;
  const _BubbleSpec(this.cx, this.cy, this.width, this.icon);
}

const _bubbles = [
  _BubbleSpec(0.50, 0.08, 0.42, Icons.sell_rounded),
  _BubbleSpec(0.28, 0.40, 0.42, Icons.event_rounded),
  _BubbleSpec(0.60, 0.70, 0.42, Icons.work_rounded),
];

class _CollagePage extends StatelessWidget {
  const _CollagePage();

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return ColoredBox(
      color: t.primarySoft,
      child: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, box) {
            final w = box.maxWidth;
            final h = box.maxHeight;
            return Stack(
              clipBehavior: Clip.none,
              children: [
                for (final o in _ovals)
                  Positioned(
                    left: o.cx * w - o.diameter * w / 2,
                    top: o.cy * h - o.diameter * w / 2,
                    width: o.diameter * w,
                    height: o.diameter * w,
                    child: ExcludeSemantics(
                      child: ClipOval(
                        child: Image.asset(
                          _assets[o.asset],
                          fit: BoxFit.cover,
                          alignment: o.crop,
                        ),
                      ),
                    ),
                  ),
                for (final b in _bubbles)
                  Positioned(
                    left: b.cx * w - b.width * w / 2,
                    top: b.cy * h,
                    width: b.width * w,
                    child: _IconBubble(icon: b.icon),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Bulle décorative : pastille orange et deux lignes grises.
class _IconBubble extends StatelessWidget {
  final IconData icon;
  const _IconBubble({required this.icon});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    Widget line(double factor) => FractionallySizedBox(
          widthFactor: factor,
          child: Container(
            height: 6,
            decoration: BoxDecoration(
              color: t.handle,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        );
    return ExcludeSemantics(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(_bubbleRadius),
          boxShadow: t.cardShadow,
        ),
        child: Row(
          children: [
            SizedBox(
              width: _bubbleDot,
              height: _bubbleDot,
              child: OverflowBox(
                maxWidth: 48,
                maxHeight: 48,
                child: RoundIconButton(
                  icon: icon,
                  style: RoundButtonStyle.primary,
                  size: _bubbleDot,
                  tooltip: '',
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [line(1), const SizedBox(height: 6), line(0.6)],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
