# Nouvelle UI « sombre et orange » Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restyle CampusConnect's shared shell and the Utilisateurs module in the validated dark/orange design, in complete light and dark themes, with a responsive layout, charts, student-card review and admin screens.

**Architecture:** Design tokens live in a `ThemeExtension` (`AppTokens`) consumed by `AppTheme.light` / `AppTheme.dark`; a `ThemeProvider` persists the mode in `shared_preferences`. Shared widgets in `lib/widgets/` are rebuilt on the tokens (existing public widgets used by other modules keep their constructors), then the shell, onboarding, visitor home, auth, home, profile, student card and admin screens are rebuilt on those widgets. Data changes are confined to `AppUser`, the two rules files and one new queue action type.

**Tech Stack:** Flutter 3.47 / Dart 3.13, Provider, Firebase (Auth, Firestore, Storage), Hive, `shared_preferences` (new), `fl_chart` (new), `google_fonts` (Outfit + Inter), `mocktail`, `fake_cloud_firestore`, `firebase_auth_mocks`.

**Spec:** `docs/superpowers/specs/2026-10-28-nouvelle-ui-design.md`

## Global Constraints

- Branch `nouvelle-ui` in `/Users/macbook/mobile/Projet_Mobile`; never touch `docs/PROMPT_CampusConnect.md` or `web/`.
- UI copy in French, sentence case; code, identifiers and commit messages in English.
- No emoji anywhere in UI copy or icons; Material icons only.
- No hex colour or font size inside a screen file: everything comes from `AppTokens` / `Theme.of(context).textTheme`.
- No text below 13 px; touch targets ≥ 48 dp; animations ≤ 200 ms and skipped when `MediaQuery.disableAnimations`.
- Widgets used by the other four modules keep their constructors: `PrimaryButton`, `StatusBadge`, `SectionCard`, `SettingsTile`, `EmptyState`, `OfflineBanner`. Files under `lib/screens/vente_don`, `annonces`, `evenements`, `stages_emploi` are never edited.
- Every task ends with `flutter analyze` reporting "No issues found!" and `flutter test` all green, then one commit.
- Tests that pump a screen use `AppTheme.light` (and `AppTheme.dark` where stated), physical size 420 × 1000 unless the test is about layout.

## Review Focus

1. Text scale 1.3 on the profile bottom bar: "Membre depuis sept. 2024" plus the pill must wrap, not overflow (Task 15 test).
2. A rejected student card re-submitted offline, then the network returns: the queue must upload the new photo and set `status: pending`, never resend an old file (Task 16 test).
3. Admin demotes themself from admin to student: the app must refuse (confirmation disabled) rather than lock the last admin out (Task 17 test).
4. Dark mode with an image that fails to load: `PhotoCard` shows the soft placeholder, never a white block (Task 4 test).
5. A 360 × 640 phone with the keyboard open on the login sheet: the hero shrinks to 120 dp and the primary button stays reachable (Task 10 test).

---

### Task 1: Design tokens and the two themes

**Files:**
- Create: `lib/core/theme/app_tokens.dart`, `lib/core/theme/contrast.dart`
- Modify: `lib/core/theme/app_theme.dart` (rewrite), `lib/core/theme/app_colors.dart` (keep file, add `@Deprecated` note pointing to tokens; values untouched so old screens compile), `pubspec.yaml` (run `flutter pub add fl_chart shared_preferences` to take the latest stable versions)
- Test: `test/core/theme/app_tokens_test.dart`, `test/core/theme/contrast_test.dart`

**Interfaces:**
- Produces: `class AppTokens extends ThemeExtension<AppTokens>` with `const` fields `Color primary, primarySoft, onPrimarySoft, background, surface, surfaceMuted, outline, textPrimary, textSecondary, success, successSoft, warning, warningSoft, danger, dangerSoft, handle; LinearGradient heroGradient; List<BoxShadow> cardShadow, navShadow;` (heroGradient: light `#FF6A1F → #F0561E`, dark `#FF7A3A → #D9541A`, top-left to bottom-right) constants `AppTokens.light`, `AppTokens.dark` (values from spec §3.1; dark shadows are empty lists); `static AppTokens of(BuildContext context)`.
- Produces: `AppTheme.light`, `AppTheme.dark` (`ThemeData`), built by `static ThemeData _build(AppTokens t, Brightness b)`: `colorScheme` from `ColorScheme.fromSeed(seedColor: t.primary, brightness: b)` overridden with `primary: t.primary, surface: t.surface, error: t.danger, outline: t.outline`; `scaffoldBackgroundColor: t.background`; `extensions: [t]`; text theme as today (Outfit/Inter) recoloured with `t.textPrimary` / `t.textSecondary`; `InputDecorationTheme` filled `t.surfaceMuted`, radius 14, focused border `t.primary` 1.6; `FilledButton`/`ElevatedButton` stadium, `t.primary`; `ChipTheme` background `t.surfaceMuted`; `SwitchTheme` track `t.primary` when selected; `BottomSheetTheme` radius 28; `DividerTheme` `t.outline`.
- Produces: `double contrastRatio(Color a, Color b)` (WCAG relative luminance).

- [ ] **Step 1: Write the failing tests**

```dart
// test/core/theme/contrast_test.dart
test('black on white is 21:1', () => expect(contrastRatio(Colors.black, Colors.white), closeTo(21, 0.01)));

// test/core/theme/app_tokens_test.dart
for (final (name, t) in [('light', AppTokens.light), ('dark', AppTokens.dark)]) {
  test('$name body text pairs reach AA 4.5', () {
    expect(contrastRatio(t.textPrimary, t.background), greaterThanOrEqualTo(4.5));
    expect(contrastRatio(t.textPrimary, t.surface), greaterThanOrEqualTo(4.5));
    expect(contrastRatio(t.textSecondary, t.surface), greaterThanOrEqualTo(4.5));
    expect(contrastRatio(t.onPrimarySoft, t.primarySoft), greaterThanOrEqualTo(4.5));
    expect(contrastRatio(t.success, t.successSoft), greaterThanOrEqualTo(4.5));
  });
  test('$name white on primary reaches 3:1 (large bold text)', () =>
      expect(contrastRatio(Colors.white, t.primary), greaterThanOrEqualTo(3)));
}
testWidgets('themes expose the tokens', (tester) async {
  await tester.pumpWidget(MaterialApp(theme: AppTheme.light, darkTheme: AppTheme.dark, themeMode: ThemeMode.dark,
      home: Builder(builder: (c) { expect(AppTokens.of(c).background, AppTokens.dark.background); return const SizedBox(); })));
});
test('light has shadows, dark has none', () { expect(AppTokens.light.cardShadow, isNotEmpty); expect(AppTokens.dark.cardShadow, isEmpty); });
```

- [ ] **Step 2: Run them to verify they fail** — `flutter test test/core/theme` → compile errors (`AppTokens` undefined).
- [ ] **Step 3: Add the two dependencies, run `flutter pub get`**.
- [ ] **Step 4: Implement `contrast.dart`, `app_tokens.dart`, rewrite `app_theme.dart`** per Interfaces. If a token pair fails AA, darken the foreground token (not the background) until it passes and record the final hex in the spec §3.1.
- [ ] **Step 5: Run `flutter test test/core/theme` → PASS; `flutter test` → all green** (old screens still compile on `AppColors`).
- [ ] **Step 6: Commit** `feat(theme): add AppTokens, light and dark themes, contrast helper`

---

### Task 2: Preferences, ThemeProvider and app bootstrap

**Files:**
- Create: `lib/services/app_prefs.dart`, `lib/providers/theme_provider.dart`
- Modify: `lib/main.dart`
- Test: `test/services/app_prefs_test.dart`, `test/providers/theme_provider_test.dart`

**Interfaces:**
- Produces: `class AppPrefs { AppPrefs(SharedPreferences prefs); static Future<AppPrefs> load(); ThemeMode get themeMode; Future<void> setThemeMode(ThemeMode m); bool get onboardingSeen; Future<void> setOnboardingSeen(); bool get biometricUnlock; Future<void> setBiometricUnlock(bool v); }` keys `'theme_mode'` (`'system'|'light'|'dark'`, default system), `'onboarding_seen'` (bool, default false) and `'biometric_unlock'` (bool, default true).
- Produces: `class ThemeProvider extends ChangeNotifier { ThemeProvider(AppPrefs prefs); ThemeMode get mode; Future<void> setMode(ThemeMode m); }`.
- Produces: `CampusConnectApp({required AppPrefs prefs})`; `MaterialApp(theme: AppTheme.light, darkTheme: AppTheme.dark, themeMode: context.watch<ThemeProvider>().mode)`; `main()` calls `await initializeDateFormatting('fr_FR')` and `final prefs = await AppPrefs.load()` before `runApp`.

- [ ] **Step 1: Write the failing tests** using `SharedPreferences.setMockInitialValues({})`:

```dart
test('defaults: system mode, onboarding not seen');
test('setThemeMode persists "dark" under theme_mode');
test('setOnboardingSeen persists true');
test('biometricUnlock defaults to true and persists false');
test('ThemeProvider notifies and persists', () async { var n = 0; p.addListener(() => n++); await p.setMode(ThemeMode.dark); expect(n, 1); expect(prefs.themeMode, ThemeMode.dark); });
```

- [ ] **Step 2: Run → fail (classes undefined).**
- [ ] **Step 3: Implement `AppPrefs`, `ThemeProvider`; wire `main.dart`** (add `ChangeNotifierProvider(create: (_) => ThemeProvider(prefs))`, import `package:intl/date_symbol_data_local.dart`).
- [ ] **Step 4: Run `flutter test` → green.** Boot check: `flutter run -d emulator-5554 --dart-define=USE_EMULATOR=true` opens without the `LocaleDataException` on the Événements tab (stop the app afterwards).
- [ ] **Step 5: Commit** `feat(core): AppPrefs, ThemeProvider, fr_FR date init`

---

### Task 3: Shared widgets, batch 1 (atoms)

**Files:**
- Create: `lib/widgets/round_icon_button.dart`, `lib/widgets/status_chip.dart`, `lib/widgets/filter_chip_pill.dart`, `lib/widgets/stat_tile.dart`, `lib/widgets/initials_avatar.dart`, `lib/widgets/skeleton_box.dart`
- Modify (restyle on tokens, same constructors): `lib/widgets/pill_button.dart` (new API, see below; only auth screens use it), `lib/widgets/primary_button.dart`, `lib/widgets/status_badge.dart` (becomes a thin wrapper over `StatusChip`), `lib/widgets/empty_state.dart`
- Test: `test/widgets/round_icon_button_test.dart`, `status_chip_test.dart`, `filter_chip_pill_test.dart`, `stat_tile_test.dart`, `initials_avatar_test.dart`, `pill_button_test.dart` (rewrite), `primary_button_test.dart` (keep, adjust colours), plus `test/helpers/pump_themed.dart`

**Interfaces:**
- Produces helper: `Future<void> pumpThemed(WidgetTester t, Widget child, {Brightness brightness = Brightness.light, Size size = const Size(420, 1000), double textScale = 1})` wrapping in `MaterialApp(theme: AppTheme.light, darkTheme: AppTheme.dark, themeMode: ...)`; and `void expectNoSmallText(WidgetTester t)` (every `Text` effective font size ≥ 13) and `void expectTapTargets(WidgetTester t)` (every `InkWell`/`GestureDetector` with `onTap` ≥ 48 × 48 including `Padding`).
- `RoundIconButton({required IconData icon, VoidCallback? onPressed, RoundButtonStyle style = RoundButtonStyle.surface, double size = 38, String? tooltip, bool showDot = false})`; `enum RoundButtonStyle { surface, soft, primary, onPhoto }` (onPhoto = always white with `AppTokens.light.textPrimary` icon).
- `PillButton({required String label, required VoidCallback? onPressed, PillStyle style = PillStyle.primary, bool isLoading = false, IconData? icon, bool expand = true})`; `enum PillStyle { primary, ghost, dark, danger }` (ghost = surface fill, 1.5 dp `primary` border, `primary` text; danger = `dangerSoft` fill, `danger` text; dark = `AppTokens.dark.surface` fill, white text, for use on photos).
- `PrimaryButton` keeps its constructor and delegates to `PillButton(style: primary)`.
- `StatusChip({required String label, StatusChipStyle style = StatusChipStyle.soft, IconData? icon})`; `enum StatusChipStyle { soft, success, warning, danger, neutral, onPhoto }`; radius 10, text 12 w600. `StatusBadge.success/warning/info/danger` map to `success/warning/neutral/danger`.
- `FilterChipPill({required String label, IconData? icon, required bool selected, VoidCallback? onTap})`.
- `StatTile({required String value, required String label, Color? valueColor})`.
- `InitialsAvatar({required String initials, String? photoUrl, double size = 42, bool verified = false, VoidCallback? onTap})` (orange circle, white initials, `cached_network_image` when url; check badge `primary` with white tick when verified).
- `SkeletonBox({double? width, double? height, double radius = 12})` (shimmer on `surfaceMuted`).

- [ ] **Step 1: Write `pump_themed.dart` and the failing widget tests.** Each new widget gets, for both brightnesses: renders label/icon; `expectNoSmallText`; tap target ≥ 48; style-specific assertions:

```dart
testWidgets('RoundIconButton onPhoto is white in dark mode', ...) // Container color == Colors.white
testWidgets('RoundIconButton showDot paints a primary dot', ...)  // find.byKey(Key('dot'))
testWidgets('PillButton ghost has primary border and text', ...)
testWidgets('PillButton loading hides label, shows spinner, ignores taps', ...)
testWidgets('StatusChip success uses successSoft/success in light and dark', ...)
testWidgets('StatusBadge.info still builds (module compatibility)', ...)
testWidgets('FilterChipPill selected is primary with white label', ...)
testWidgets('InitialsAvatar verified shows the check badge', ...)
testWidgets('StatTile valueColor overrides', ...)
```

- [ ] **Step 2: Run `flutter test test/widgets` → fail.**
- [ ] **Step 3: Implement the widgets.** Update the three auth screens' imports only enough to compile with the new `PillButton` signature (`width`/`background`/`foreground` removed → keep their visual via `style: PillStyle.primary`; full restyle happens in Task 10).
- [ ] **Step 4: `flutter test` → green** (adjust `pill_button_test.dart`, `primary_button_test.dart` to the new palette; functional tests unchanged).
- [ ] **Step 5: Commit** `feat(widgets): atoms on AppTokens (round button, pill, chips, stat tile, avatar, skeleton)`

---

### Task 4: Shared widgets, batch 2 (molecules)

**Files:**
- Create: `lib/widgets/photo_card.dart`, `lib/widgets/featured_card.dart`, `lib/widgets/search_pill.dart`, `lib/widgets/sync_chip.dart`, `lib/widgets/setting_row.dart` (contains `SettingRow` and `SettingGroup`), `lib/widgets/hero_sheet_scaffold.dart`, `lib/widgets/floating_nav_bar.dart`
- Modify: `lib/widgets/section_card.dart` (restyle on tokens: `SectionCard` = `SettingGroup` look; `SettingsTile` = `SettingRow` look, same constructors), `lib/widgets/offline_banner.dart` (tokens `warningSoft`/`warning`), `lib/core/constants/layout.dart` (add `const double kFloatingNavInset = 96.0; const double kCompactBreakpoint = 600.0; const double kContentMaxWidth = 720.0;`)
- Test: one test file per new widget under `test/widgets/`

**Interfaces:**
- `PhotoCard({String? imageUrl, IconData placeholderIcon = Icons.image_outlined, StatusChip? chip, bool showHeart = false, bool favorite = false, VoidCallback? onHeart, required String title, Widget? meta, Widget? footer, VoidCallback? onTap, double imageHeight = 120, double? width})`. Image via `CachedNetworkImage` with `errorWidget`/`placeholder` = `primarySoft` box with the icon.
- `FeaturedCard({String? imageUrl, required String chipLabel, required String title, required List<FeaturedMeta> meta, required String actionLabel, VoidCallback? onAction, VoidCallback? onTap, double height = 170})`; `class FeaturedMeta { const FeaturedMeta(this.icon, this.text); }`. Orange gradient overlay left → transparent, text white, action `PillButton(style: dark, expand: false)`.
- `SearchPill({required String hint, VoidCallback? onTap, VoidCallback? onFilter})`.
- `SyncChip({required bool online, required int pending})` → `'À jour'` (success) when online && pending == 0; `'$pending en attente'` (warning) when online && pending > 0; `'Hors ligne'` (warning, wifi-off icon) when offline.
- `SettingRow({required IconData icon, required String title, String? subtitle, Widget? trailing, VoidCallback? onTap, bool destructive = false, Key? key})`; `SettingGroup({String? title, required List<Widget> children})`.
- `HeroSheetScaffold({required Widget hero, Widget? heroLeading, List<Widget> heroActions = const [], required List<Widget> children, Widget? bottomBar, bool showHandle = true, double heroFraction = 0.34, double minHeroHeight = 200, double maxHeroHeight = 320, double keyboardHeroHeight = 120})`. Layout: `LayoutBuilder`; hero height = `clamp(height * heroFraction, min, max)`, or `keyboardHeroHeight` when `MediaQuery.viewInsets.bottom > 0` or height < 560; sheet = `surface`, top radius 28, negative top margin 28, handle; content scrolls inside `SafeArea`; `bottomBar` fixed with top radius 24 and `navShadow`; children get bottom padding `bottomBar == null ? 24 : 112`. Width > `kCompactBreakpoint`: content centred, max `kContentMaxWidth`.
- `FloatingNavBar({required int index, required ValueChanged<int> onChanged, required List<FloatingNavItem> items})`; `class FloatingNavItem { const FloatingNavItem({required this.icon, required this.label}); }`; pill `surface` with `navShadow` (dark: `outline` border), 46 dp `RoundIconButton`s, active `primary`; `Semantics(label: item.label, selected:)`; max width 480 centred; sits 16 dp above the bottom safe inset.

- [ ] **Step 1: Write the failing tests** (both brightnesses where colour matters):

```dart
testWidgets('PhotoCard without url shows the soft placeholder, in dark too') // Container color == tokens.primarySoft
testWidgets('PhotoCard heart toggles via onHeart and reflects favorite')
testWidgets('FeaturedCard shows chip, title, meta and calls onAction')
testWidgets('SyncChip labels: À jour / 2 en attente / Hors ligne')
testWidgets('SettingRow destructive uses danger colour; trailing replaces chevron')
testWidgets('HeroSheetScaffold hero is 34% clamped to [200,320] at 420x1000 → 320; at 360x640 → 217.6')
testWidgets('HeroSheetScaffold shrinks hero to 120 when viewInsets.bottom > 0')
testWidgets('HeroSheetScaffold centres content at 800 wide (content width == 720)')
testWidgets('FloatingNavBar highlights index and calls onChanged; 5 semantics labels')
testWidgets('FloatingNavBar never exceeds 480 wide at 800x1280')
```

- [ ] **Step 2: Run → fail.**
- [ ] **Step 3: Implement the widgets and restyle `section_card.dart`, `offline_banner.dart`.**
- [ ] **Step 4: `flutter test` → green.**
- [ ] **Step 5: Commit** `feat(widgets): photo/featured cards, search pill, sync chip, setting rows, hero sheet scaffold, floating nav bar`

---

### Task 5: Chart wrappers and the design gallery

**Files:**
- Create: `lib/widgets/charts/chart_models.dart`, `lib/widgets/charts/area_line_chart.dart`, `lib/widgets/charts/donut_chart.dart`, `lib/widgets/charts/h_bar_chart.dart`, `lib/screens/debug/design_gallery_screen.dart`
- Test: `test/widgets/charts/charts_test.dart`, `test/screens/design_gallery_screen_test.dart`

**Interfaces:**
- `class ChartPoint { const ChartPoint({required this.label, required this.value}); final String label; final double value; }`; `class ChartSlice { const ChartSlice({required this.label, required this.value, required this.color}); }`; `class ChartBar` same fields as `ChartSlice`.
- `AreaLineChart({required List<ChartPoint> points, String emptyText = 'Pas encore de données', String Function(ChartPoint p)? tooltip, double height = 160})`: `fl_chart` `LineChart`, `primary` line 2.5, gradient area `primary` 35 % → 0 %, grid `outline`, x labels every `max(1, points.length ~/ 5)` points, touch tooltip `surface` bubble; `points.isEmpty` → `Center(Text(emptyText))`.
- `DonutChart({required List<ChartSlice> slices, String? centerLabel, double size = 120})`: `PieChart` with `centerSpaceRadius`, legend column to the right (`label percent %`); empty → `emptyText`.
- `HBarChart({required List<ChartBar> bars, double barHeight = 12})`: rows `label | rounded bar (width ∝ value / max) | value`; built with `Row`s (no `fl_chart` needed) so it animates with `AnimatedContainer` ≤ 200 ms.
- `DesignGalleryScreen` (`kDebugMode` only): one scrollable page listing every token swatch, text style, button style, chip style, cards, rows, nav bar, three charts, in the current theme, with a theme-mode segmented control on top.

- [ ] **Step 1: Write failing tests**: each chart renders with data (finds `LineChart` / `PieChart` / 3 bars), renders `emptyText` when empty, no small text; gallery renders in light and dark and `expectNoSmallText`.
- [ ] **Step 2: Run → fail. Step 3: Implement. Step 4: `flutter test` → green.**
- [ ] **Step 5: Commit** `feat(charts): fl_chart wrappers and design gallery`

---

### Task 6: App shell with the floating bar

**Files:**
- Modify: `lib/screens/home/app_shell.dart`, `lib/screens/home/home_screen.dart` (`HomeTabs`: remove `profile`; `onAvatar` pushes `ProfileScreen`; only this change here), `lib/screens/profile/profile_screen.dart` (wrap body in `Scaffold` with leading back — only enough to be pushed; full restyle in Task 15)
- Test: `test/screens/app_shell_test.dart`, update `test/screens/home_screen_test.dart` (avatar expectation)

**Interfaces:**
- `AppShell({int initialIndex = 0})`: `Scaffold(extendBody: true, body: Stack([IndexedStack(5 screens), Positioned(bottom) FloatingNavBar]))`; items in order Accueil `Icons.home_rounded`, Marché `Icons.sell_rounded`, Annonces `Icons.campaign_rounded`, Événements `Icons.event_rounded`, Stages `Icons.work_rounded`. Each tab screen is wrapped in `MediaQuery.removePadding` + `Padding(bottom: kFloatingNavInset)` so module lists clear the bar without editing module files.
- `HomeTabs.profile` removed; `HomeScreen.onAvatar` → `Navigator.push(ProfileScreen())`.

- [ ] **Step 1: Write failing tests**: shell shows 5 `FloatingNavItem`s and no `BottomNavigationBar`; tapping "Annonces" switches the `IndexedStack` index; home avatar tap pushes `ProfileScreen` (use `AuthHarness` + mocked module providers as `home_screen_test.dart` does).
- [ ] **Step 2: Run → fail. Step 3: Implement. Step 4: `flutter test` → green.**
- [ ] **Step 5: Commit** `feat(shell): floating five-item nav bar, profile pushed from avatar`

---

### Task 7: Onboarding

**Files:**
- Create: `lib/screens/onboarding/onboarding_screen.dart`, `assets/images/onboarding/campus_1.jpg`, `campus_2.jpg`, `campus_3.jpg` (CC0 photos, each ≤ 200 KB, 1080 px wide; record the source URLs in `docs/decisions.md`)
- Modify: `lib/main.dart` (`_RootRouter`: show `OnboardingScreen` when `!prefs.onboardingSeen && status == visitor`), `pubspec.yaml` assets entry
- Test: `test/screens/onboarding_screen_test.dart`, `test/main_root_router_test.dart`

**Interfaces:**
- `OnboardingScreen({required AppPrefs prefs, VoidCallback? onStart, VoidCallback? onLogin})`: `PageView` of 3 pages; page 1 = bubble collage (`ClipOval` photos + three `_IconBubble`s with `RoundIconButton(style: primary)` and two grey lines); pages 2–3 full photo; sheet below with title `Text.rich` (Outfit 800, last segment italic `primary`), subtitle, dots, `PillButton` « Commencer », link « Déjà un compte ? Se connecter ». Copy: page 1 "Toute la vie du campus, *au même endroit*" / "Marché, annonces, événements et stages. Même sans connexion."; page 2 "Vends, donne, *trouve*" / "Objets, livres et services entre étudiants, autour de toi."; page 3 "Ne rate *rien*" / "Annonces officielles, événements et offres de stage en un seul fil." Both actions call `prefs.setOnboardingSeen()` then the callback.

- [ ] **Step 1: Failing tests**: three pages swipe; « Commencer » marks seen and calls `onStart`; link calls `onLogin`; root router shows onboarding only once (`SharedPreferences.setMockInitialValues`); no small text at 360 × 640.
- [ ] **Step 2–4: fail → implement → green.**
- [ ] **Step 5: Commit** `feat(onboarding): three-page onboarding shown once`

---

### Task 8: Visitor home restyle

**Files:**
- Modify: `lib/screens/visitor/visitor_home_screen.dart`
- Test: `test/screens/visitor_home_screen_test.dart` (replace the gradient/`surfaceTone` assertions; keep functional ones)

**Interfaces:** hero = `Stack` with `assets/images/onboarding/campus_2.jpg`, dark gradient overlay, wordmark, headline, two `StatusChip(style: onPhoto)` stat pills; sections use `PhotoCard` (articles, offers), `FeaturedCard` (first event), notice cards as `SettingGroup` rows; bottom bar: `PillButton` « Créer un compte étudiant » + `PillButton(style: ghost)` « Se connecter »; loading = `SkeletonBox`.

- [ ] **Step 1: Update tests first**: hero shows the image asset and no `brandGradient`; CTA buttons are `PillButton`s; 360 px no overflow; both themes no small text.
- [ ] **Step 2–4: fail → implement → green.** **Step 5: Commit** `feat(visitor): restyle visitor home on the new components`

---

### Task 9: Auth text field and auth feedback on tokens

**Files:**
- Modify: `lib/widgets/auth/auth_text_field.dart` (tokens, radius 14, `surfaceMuted` fill), `lib/widgets/auth/auth_feedback.dart` (`AuthErrorBanner` on `dangerSoft`/`danger`; drop `onDark`), `lib/widgets/auth/password_strength_meter.dart` (drop `onDark`, colours `danger/warning/success`), `lib/widgets/social_icon_row.dart` (round `surface` buttons with `outline`)
- Delete: `lib/widgets/underline_text_field.dart`, `lib/core/theme/auth_text_styles.dart`, `test/widgets/underline_text_field_test.dart`
- Test: `test/widgets/auth_text_field_test.dart`, `test/widgets/social_icon_row_test.dart` (update)

- [ ] **Step 1: Failing tests**: `AuthTextField` fill is `surfaceMuted`, error text is `tokens.danger`, password reveal works; `AuthErrorBanner` renders on `dangerSoft`.
- [ ] **Step 2–4: fail → implement → green** (temporarily keep auth screens compiling by removing the `onDark:` arguments; they are rebuilt next task).
- [ ] **Step 5: Commit** `refactor(auth-widgets): fields, banner, strength meter and social row on tokens`

---

### Task 10: Auth screens on HeroSheetScaffold

**Files:**
- Modify: `lib/screens/auth/login_screen.dart`, `register_screen.dart`, `forgot_password_screen.dart`, `otp_verification_screen.dart`, `lib/screens/profile/change_password_screen.dart`
- Delete: `lib/widgets/gradient_scaffold.dart`, `test/widgets/gradient_scaffold_test.dart`
- Create: `lib/widgets/auth/auth_hero.dart`
- Test: rewrite the `UI contract (gradient style)` groups in `test/screens/login_screen_test.dart` and `register_screen_test.dart`; adjust the other three screen tests' colour assertions

**Interfaces:**
- `AuthHero({required String title, required String subtitle, required IconData icon})`: `AppTokens.heroGradient` background, two translucent circles, white icon tile, white title (Outfit 700, 30), white subtitle.
- `LoginScreen({LoginPrefs? prefs, AppPrefs? appPrefs})`: the biometric `SocialIconItem` is shown only when `auth.canUnlockWithBiometrics && (appPrefs?.biometricUnlock ?? true)`.
- Each screen = `HeroSheetScaffold(hero: AuthHero(...), heroLeading: RoundIconButton(onPhoto, back) when canPop, children: [form…])`. Login: email field with domain `ActionChip` (tokens), password field, « Se souvenir de moi » checkbox + « Mot de passe oublié ? » text button (`primary`), `AuthErrorBanner`, `PillButton` « Se connecter », `SocialIconRow` (Google, biometrics when available), footer « Pas encore de compte ? Créer un compte ». Register, forgot, OTP, change-password: same field list as today, `PillButton` for the main action.

- [ ] **Step 1: Rewrite the contract tests** (names kept, bodies new):

```dart
group('UI contract (hero sheet)', () {
  testWidgets('is built from HeroSheetScaffold with an AuthHero and no GradientScaffold');
  testWidgets('the main action is a primary PillButton that spans the sheet');
  testWidgets('field errors use the danger token');           // find.text('Email requis') color == tokens.danger
  testWidgets('keyboard open shrinks the hero to 120 dp at 360x640');  // MediaQuery viewInsets 300
  testWidgets('the biometric button is hidden when biometric_unlock is false');
  testWidgets('no text under 13 px in light and dark');
});
```

- [ ] **Step 2: Run → fail. Step 3: Implement the five screens. Step 4: `flutter test` → green** (functional tests untouched: validation, OTP, prefs, errors).
- [ ] **Step 5: Commit** `feat(auth): login, register, forgot, OTP and change-password on the hero sheet`

---

### Task 11: Home dashboard restyle

**Files:**
- Modify: `lib/screens/home/home_screen.dart` (replace private widgets with shared ones; keep `_Completion`, `_CampusSearch`, `_Fr`, data selection logic)
- Test: `test/screens/home_screen_test.dart` (keep every functional test; update colour/structure ones)

**Interfaces:** order per spec §5.4: `_Header` (InitialsAvatar → profile, « Campus » / « ESPRIT Ghazela » with `Icons.location_on_rounded` in `primary`, `RoundIconButton(bell, showDot: unread > 0)`), row(date, `SyncChip`), `SearchPill`, « À la une » = `PageView` of `FeaturedCard`s (pinned official notices then the featured event; dots), « Modules » = four `FilterChipPill`s (selected = none; subtitle counts in a `Wrap`), `_CompletionCard` (ring via `DonutChart(size: 52)` with one slice, `PillButton(expand: false)` « Compléter »), « Cette semaine » card (date block on `primarySoft`, `PillButton(style: ghost, expand: false)` « Je participe » / `StatusChip` « Inscrit »), « Stages pour toi » `PhotoCard(width: 168)` list with company initial tile and `StatusChip` « n % match » when `recommendedFor` scored (use `offer.requiredSkills` overlap ratio), « Vente & Don » `GridView.count(crossAxisCount: width < 600 ? 2 : 3)` of `PhotoCard`s. Layout: `LayoutBuilder`, content max 720 centred when wide.

- [ ] **Step 1: Update tests**: header has `InitialsAvatar` and `SyncChip`; four `FilterChipPill`s switch tabs; featured `FeaturedCard` shows the pinned notice; grid is 2 columns at 420 and 3 at 800; no overflow at 360; both themes no small text.
- [ ] **Step 2–4: fail → implement → green.** **Step 5: Commit** `feat(home): dashboard on the new components, responsive grid`

---

### Task 12: Home activity chart

**Files:**
- Create: `lib/core/utils/activity_stats.dart`
- Modify: `lib/screens/home/home_screen.dart` (append « Mon activité, 7 jours » card)
- Test: `test/core/activity_stats_test.dart`, add one test to `home_screen_test.dart`

**Interfaces:**
- `List<ChartPoint> weeklyActivity({required String userId, required List<ArticleModel> articles, required List<AnnonceModel> notices, required List<EventModel> events, required List<ApplicationModel> applications, required DateTime now})`: 7 points, oldest first, labels `_Fr.dayShort` of each day, value = count of `articles.where(ownerId == userId && createdAt on that day)` + `notices.where(authorId == userId …)` + `events.where(organizerId == userId && startDate on that day)` + `applications.where(candidateId == userId && appliedAt on that day)`.

- [ ] **Step 1: Failing tests**: 7 points; sums across the four sources; ignores other users; today is the last point; all-zero still returns 7 points (chart shows the empty text only when every value is 0 → assert `AreaLineChart` receives `emptyText` behaviour: home shows « Aucune activité cette semaine »).
- [ ] **Step 2–4: fail → implement → green.** **Step 5: Commit** `feat(home): weekly activity chart`

---

### Task 13: User model, constants and security rules

**Files:**
- Modify: `lib/models/user_model.dart`, `lib/core/constants/app_constants.dart`, `firestore.rules`, `storage.rules`, `lib/services/auth_service.dart` (`registerWithEmail` and Google first-profile creation set `campus: AppConstants.defaultCampus`, `studentCard: StudentCard.none`)
- Create: `test/rules/package.json`, `test/rules/firestore.rules.test.mjs`, `test/rules/README.md`
- Test: `test/models/user_model_test.dart` (extend), rules tests

**Interfaces:**
- `enum StudentCardStatus { none, pending, verified, rejected }`; `class StudentCard { const StudentCard({this.status = StudentCardStatus.none, this.imagePath, this.submittedAt, this.reviewedBy, this.reviewedAt, this.rejectReason}); static const none = StudentCard(); factory fromMap(Map?); Map<String, dynamic> toMap(); StudentCard copyWith(...); }`.
- `AppUser` gains `final String campus; final String? studentId; final bool disabled; final StudentCard studentCard;` (defaults `AppConstants.defaultCampus`, null, false, `StudentCard.none`), in `fromMap`/`toMap`/`copyWith`; `editableFields` adds `'campus', 'studentId', 'studentCard'`.
- `AppConstants.defaultCampus = 'ESPRIT Ghazela'`; `AppConstants.departments = ['Génie Informatique', 'Génie Civil', 'Génie Électromécanique', 'Génie Télécom', 'Génie Industriel', 'Business', 'Autre']`.
- Rules exactly as spec §6.2 / §6.3. Rules test script runs `firebase emulators:exec --only firestore "node --test"` with `@firebase/rules-unit-testing`; cases: owner cannot set `studentCard.status: verified`; owner can set `pending` with `imagePath`; owner cannot set `disabled`; admin can set `verified` + `isVerifiedStudent`; create with `disabled: true` denied.

- [ ] **Step 1: Failing Dart tests**: `AppUser.fromMap` without the new keys gives defaults; round-trip `toMap`/`fromMap` keeps `studentCard`; `toEditableMap` contains `studentCard` but never `disabled`.
- [ ] **Step 2: Run → fail. Step 3: Implement model + constants + service defaults. Step 4: `flutter test` → green.**
- [ ] **Step 5: Write the rules tests, run `cd test/rules && npm install && npm test` → the new cases fail against the old rules.**
- [ ] **Step 6: Edit `firestore.rules` and `storage.rules`; `npm test` → pass.**
- [ ] **Step 7: Commit** `feat(users): student card and disabled fields, departments, rules`

---

### Task 14: Edit profile with department dropdown

**Files:**
- Modify: `lib/screens/profile/edit_profile_screen.dart`, `lib/core/utils/validators.dart` (`major` accepts any value from `departments` or a free text when « Autre »)
- Test: `test/screens/edit_profile_screen_test.dart`

**Interfaces:** `DropdownButtonFormField<String>(key: Key('department-dropdown'))` on `AppConstants.departments`; when « Autre », an `AuthTextField(key: Key('department-other'))` appears; `studentId` text field (optional, `Validators.studentId`: 6–12 alphanumerics); saves `major` = selected department or the free text; existing `major` outside the list preselects « Autre » with the text filled. Buttons become `PillButton`.

- [ ] **Step 1: Failing tests**: dropdown lists the 7 departments; « Autre » reveals the text field and saves its text; an existing custom major preselects « Autre »; student id validation.
- [ ] **Step 2–4: fail → implement → green.** **Step 5: Commit** `feat(profile): department dropdown and student id`

---

### Task 15: Profile screen restyle

**Files:**
- Create: `assets/images/cover_campus.jpg` (CC0, ≤ 200 KB)
- Modify: `lib/screens/profile/profile_screen.dart`
- Test: `test/screens/profile_screen_test.dart` (keep functional tests; replace structure/colour assertions)

**Interfaces:** `HeroSheetScaffold(hero: cover image + dark gradient, heroLeading: back, heroActions: [share (copies profile text), edit])`; sheet: `InitialsAvatar(size: 64, verified: user.isVerifiedStudent)` overlapping by 44 dp, name (Outfit 800), `Wrap` of `StatusChip`s: card status (`Étudiant vérifié` success / `Vérification en attente` warning / `Carte refusée` danger / none → nothing), `Email vérifié` or `Email à vérifier`, `Téléphone vérifié` when so; « major · year » line; three `StatTile`s (`Annonces` = notices by user, `Ventes` = articles by user, `Candidatures` = `myApplications.length`); `SettingRow` « Carte étudiant » (subtitle per status, opens `StudentCardScreen` from Task 16; until then opens nothing — wire in Task 16), « Connexion biométrique » toggle bound to `AppPrefs.biometricUnlock` (Task 2; read by the login screen, Task 10), « Thème » (`showModalBottomSheet` with three `RadioListTile`s → `ThemeProvider.setMode`), groups « Compte », « Sécurité », « Données & confidentialité » as today on `SettingGroup`/`SettingRow`, « Administration » group when `user.role == UserRole.admin` (rows wired in Task 17/18), « Déconnexion » `PillButton(style: danger)`; `bottomBar`: « Membre depuis <MMM yyyy fr> » + `PillButton` « Modifier le profil ».

- [ ] **Step 1: Update tests**: identity, chips per status, stats, theme sheet changes `ThemeProvider.mode`, biometric toggle persists, bottom bar wraps at text scale 1.3 without overflow (`tester.view.physicalSize = Size(360, 640)`, `MediaQuery(textScaler: 1.3)`), admin group only for admins, both themes no small text.
- [ ] **Step 2–4: fail → implement → green.** **Step 5: Commit** `feat(profile): hero sheet profile with status chips, theme and bottom bar`

---

### Task 16: Student card submission (online and queued)

**Files:**
- Create: `lib/services/student_card_service.dart`, `lib/screens/profile/student_card_screen.dart`
- Modify: `lib/core/utils/offline_queue_service.dart` (`QueueActionType.uploadStudentCard`; `syncAll(FirebaseFirestore firestore, {Future<String> Function(String localPath, String remotePath)? upload})`), `lib/providers/connectivity_provider.dart` (pass `StorageService().uploadFile`), `lib/services/storage_service.dart` (`Future<String> uploadFile(File file, {required String remotePath})` returning the storage path), `lib/providers/auth_provider.dart` (constructor gains `StudentCardService? studentCardService`, lazily built like `_storageService`; `Future<bool> submitStudentCard(File photo, {required bool isOnline})` updates `currentUser.studentCard`; `bool pendingCardQueued`), `lib/screens/profile/profile_screen.dart` (wire the row)
- Test: `test/services/student_card_service_test.dart`, `test/core/offline_queue_service_test.dart` (new, Hive in temp dir), `test/screens/student_card_screen_test.dart`

**Interfaces:**
- `class StudentCardService { StudentCardService({required StorageService storage, required FirebaseFirestore firestore, required OfflineQueueService queue, Directory Function()? appDir}); Future<StudentCard> submit({required String uid, required File photo, required bool isOnline, DateTime Function() now}); }`. Online: compress, `storage.uploadFile(remotePath: 'student_cards/$uid/${now.millisecondsSinceEpoch}.jpg')`, then `users/$uid` merge `{studentCard: {status: 'pending', imagePath, submittedAt}}`; returns the card. Offline: copy the file to `appDir()/student_card_$uid.jpg`, `queue.enqueue(type: uploadStudentCard, collection: 'users', docId: uid, payload: {'localPath': …, 'remotePath': …})`; returns `StudentCard(status: pending)` flagged locally (`AuthProvider` keeps `pendingCardQueued = true` while the action is in the box).
- `syncAll`: for `uploadStudentCard`, call `upload(localPath, remotePath)` then merge the same document patch, delete the local copy; failure keeps the action.
- `StudentCardScreen`: explanation, preview (`image_picker` gallery/camera via two `PillButton(style: ghost)`), `PillButton` « Envoyer pour validation » (disabled until a photo is picked), status block with `StatusChip` and, when rejected, the reason and « Renvoyer »; offline → chip « En attente de connexion ».

- [ ] **Step 1: Failing tests**: online submit uploads then writes `pending` (fake firestore + mock storage); offline submit enqueues one `uploadStudentCard` with the copied path; `syncAll` with `upload` stub uploads, writes, removes the action; a second offline submit after a rejection replaces the queued action (only one `uploadStudentCard` per uid in the box, pointing at the newest file); screen flow: pick → send → chip « En cours de validation ».
- [ ] **Step 2–4: fail → implement → green.** **Step 5: Commit** `feat(users): student card submission with offline queue`

---

### Task 17: Admin users, roles and card review

**Files:**
- Create: `lib/services/admin_user_service.dart`, `lib/providers/admin_users_provider.dart`, `lib/screens/admin/admin_users_screen.dart`, `lib/screens/admin/admin_card_review_screen.dart`
- Modify: `lib/screens/profile/profile_screen.dart` (Administration rows), `lib/main.dart` (`_RootRouter`: `currentUser?.disabled == true` → sign out and show visitor home with snack « Compte désactivé »), `lib/providers/auth_provider.dart` (`disabled` check in `_onAuthStateChanged`)
- Test: `test/services/admin_user_service_test.dart`, `test/providers/admin_users_provider_test.dart`, `test/screens/admin_users_screen_test.dart`, `test/screens/admin_card_review_screen_test.dart`

**Interfaces:**
- `class AdminUserService { AdminUserService(FirebaseFirestore db); Stream<List<AppUser>> watchAll(); Future<void> setRole(String uid, UserRole role); Future<void> setDisabled(String uid, bool disabled); Future<void> reviewCard({required String uid, required bool approve, String? reason, required String reviewerUid, DateTime Function() now}); Future<String> cardImageUrl(String path); }` (`reviewCard` approve → `studentCard.status verified, reviewedBy, reviewedAt, isVerifiedStudent: true`; reject → `rejected`, `rejectReason`, `isVerifiedStudent: false`).
- `class AdminUsersProvider extends ChangeNotifier { AdminUsersProvider(AdminUserService s, {required String currentAdminUid}); List<AppUser> users; String query; UserRole? roleFilter; StudentCardStatus? cardFilter; List<AppUser> get filtered; int get adminCount; bool canChangeRole(AppUser u, UserRole to) => !(u.id == currentAdminUid && to != UserRole.admin && adminCount <= 1); … }` with 400 ms debounce on `setQuery`.
- The profile's « Administration » rows push the admin screens wrapped in `ChangeNotifierProvider(create: (_) => AdminUsersProvider(AdminUserService(FirebaseFirestore.instance), currentAdminUid: user.id))`; tests inject a provider built on `FakeFirebaseFirestore`.
- `AdminUsersScreen({StudentCardStatus? initialCardFilter})`: `SearchPill` (tap focuses an inline `TextField`), `FilterChipPill`s « Étudiants / Recruteurs / Admins » and « En attente », `ListView.builder` rows (avatar, name, `StatusChip` role, `StatusChip` card status), tap → bottom sheet with « Changer le rôle » (3 `RadioListTile` + confirm `PillButton`), « Désactiver / Réactiver le compte » (`danger` pill), « Voir la carte » when pending.
- `AdminCardReviewScreen({required AppUser user})`: `HeroSheetScaffold(hero: card image (zoom on tap via `InteractiveViewer` dialog), children: identity rows, bottomBar: Row(PillButton(ghost danger) « Refuser », PillButton « Valider »))`; refuse opens a dialog with a required reason (min 5 chars).

- [ ] **Step 1: Failing tests**: service writes the exact fields for approve/reject (fake firestore); provider filters by query/role/card and debounces; `canChangeRole` false for the last admin demoting themself (confirm button disabled in the sheet); screen lists users and opens the review; review approve/reject calls the service with reason; disabled user is signed out by `_RootRouter`.
- [ ] **Step 2–4: fail → implement → green.** **Step 5: Commit** `feat(admin): users list, roles, account disable, card review`

---

### Task 18: Admin analytics

**Files:**
- Create: `lib/services/user_stats_service.dart`, `lib/screens/admin/admin_analytics_screen.dart`
- Modify: `lib/screens/profile/profile_screen.dart` (row « Statistiques »)
- Test: `test/services/user_stats_service_test.dart`, `test/screens/admin_analytics_screen_test.dart`

**Interfaces:**
- `class UserStats { final int signUps; final double? changePercent; final int pendingCards; final List<ChartPoint> signUpsPerDay; final Map<UserRole, int> byRole; final Map<StudentCardStatus, int> cardsByStatus; }`; `UserStats aggregate(List<AppUser> users, {required DateTime now, required int days})`: window = last `days` days ending today inclusive; `changePercent` vs the previous window (`null` when previous is 0); `signUpsPerDay` labels `d` (day of month) for 7 days, `d/M` otherwise; `byRole` counts all users; `cardsByStatus` all users.
- `AdminAnalyticsScreen`: period `FilterChipPill`s 7 / 30 / 90, two `StatTile`s (`Inscrits` with « + 12 % ce mois » in `success` or « − n % » in `danger`; `Cartes en attente` in `primary`), `AreaLineChart` « Inscriptions par jour » (tooltip « +n »), `DonutChart` « Par rôle » (`primary`, `primary` 60 % alpha, `textSecondary`), `HBarChart` « Vérification des cartes » (validées `primary`, en attente `warning`, refusées `handle`). Data from `AdminUsersProvider.users`.

- [ ] **Step 1: Failing tests**: `aggregate` with fixed users: counts, change percent (+100 %, null case), 7 labels, roles, card statuses; screen renders the three charts and switches period.
- [ ] **Step 2–4: fail → implement → green.** **Step 5: Commit** `feat(admin): user analytics with fl_chart`

---

### Task 19: Documentation, screenshots and final verification

**Files:**
- Create: `docs/decisions.md`, `docs/screenshots/` (light + dark of onboarding, visitor, login, register, home, profile, edit profile, student card, admin users, card review, analytics)
- Modify: `README.md` (design system section, theme mode, course-concept table rows for `shared_preferences`, `fl_chart`, `LayoutBuilder`; seed accounts for the emulator: `admin@esprit.tn`, `amel@esprit.tn`, `recruteur@vermeg.tn`, password `Campus2026!`), `tool/seed.sh` (creates those accounts and three pending cards against the emulators)
- Test: full suite

- [ ] **Step 1: Write `docs/decisions.md`**: orange vs violet, OCR dropped, nav 5 + avatar, departments list, photo sources, the `applications` rule issue for the Stage owner, Spark-plan limits for analytics.
- [ ] **Step 2: Run the app on `emulator-5554` with the emulators (`tool/run.sh emu emulator-5554`), seed, capture every screen in light then dark** (toggle via the profile « Thème » row), save as `docs/screenshots/<screen>_<light|dark>.png`.
- [ ] **Step 3: `flutter analyze` → No issues; `flutter test` → all green; `cd test/rules && npm test` → pass.**
- [ ] **Step 4: Commit** `docs: decisions, screenshots, README for the new UI`
