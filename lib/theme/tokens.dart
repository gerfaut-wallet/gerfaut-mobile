// Toundra design tokens, mapped from the Gerfaut design system.
//
// This file is the only place in the app where raw color values may
// appear. Everything else references a role on [GerfautTokens] through
// `Theme.of(context).extension<GerfautTokens>()`.

import 'package:flutter/material.dart';

/// Spacing scale, base 4px.
abstract final class GerfautSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;

  /// Mobile gutter between cards (DESIGN.md layout constant).
  static const double gutter = 12;
}

/// Corner radii. Nothing above [lg] on a container.
abstract final class GerfautRadius {
  static const double sm = 4;
  static const double md = 8;
  static const double lg = 12;
  static const double full = 9999;
}

/// QR codes stay dark-on-light in every theme: scanners expect it, and
/// inverting hurts contrast for cameras. These are the only theme-fixed
/// colors of the system.
abstract final class GerfautQr {
  static const Color background = Color(0xFFFFFFFF);
  static const Color foreground = Color(0xFF0D1317);
}

/// Font families bundled from brand assets.
abstract final class GerfautFonts {
  /// Bricolage Grotesque: display, h1, h2. Never body text.
  static const String display = 'Bricolage Grotesque';

  /// Instrument Sans: everything interface, figures included.
  static const String ui = 'Instrument Sans';

  /// JetBrains Mono: identifiers and code only — txids, addresses,
  /// descriptors, raw hex, OP_RETURN payloads, backend host and port.
  static const String data = 'JetBrains Mono';
}

/// The Toundra role palette and type scale, one instance per theme.
@immutable
class GerfautTokens extends ThemeExtension<GerfautTokens> {
  const GerfautTokens({
    required this.background,
    required this.surface,
    required this.surfaceSunken,
    required this.border,
    required this.text,
    required this.textMuted,
    required this.primary,
    required this.onPrimary,
    required this.alert,
    required this.alertSurface,
    required this.confirmed,
    required this.confirmedSurface,
    required this.pending,
    required this.pendingSurface,
    required this.display,
    required this.h1,
    required this.h2,
    required this.body,
    required this.bodySmall,
    required this.label,
    required this.amount,
    required this.figure,
    required this.data,
  });

  // --- color roles -----------------------------------------------------

  /// Page canvas.
  final Color background;

  /// Cards, panels, lists.
  final Color surface;

  /// Fields, chips, hovered states (a recess in light, a relief in dark).
  final Color surfaceSunken;

  /// Separators and outlines, always 1px.
  final Color border;

  /// Main text.
  final Color text;

  /// Metadata, labels, timestamps. The floor for text contrast.
  final Color textMuted;

  /// Action and selection only. One primary action per screen.
  final Color primary;

  /// Text on [primary].
  final Color onPrimary;

  /// Strictly reserved for an unexpected outflow or monitoring anomaly.
  final Color alert;

  /// Tinted surface behind [alert] content.
  final Color alertSurface;

  /// Confirmed incoming transaction, timelock expired as planned.
  final Color confirmed;

  /// Tinted surface behind [confirmed] content.
  final Color confirmedSurface;

  /// Awaiting confirmation, approaching timelock.
  final Color pending;

  /// Tinted surface behind [pending] content.
  final Color pendingSurface;

  // --- type scale ------------------------------------------------------

  /// 32px Bricolage 600.
  final TextStyle display;

  /// 24px Bricolage 600.
  final TextStyle h1;

  /// 18px Bricolage 600.
  final TextStyle h2;

  /// 16px Instrument 400.
  final TextStyle body;

  /// 14px Instrument 400.
  final TextStyle bodySmall;

  /// 12px Instrument 500, +0.04em.
  final TextStyle label;

  /// 32px Instrument Sans 600, tabular figures: the headline figure.
  final TextStyle amount;

  /// 13px Instrument Sans 400, tabular figures: every other figure.
  final TextStyle figure;

  /// 13px JetBrains Mono 400, tabular figures: identifiers and code.
  final TextStyle data;

  /// A figure in the UI face at an arbitrary size and weight, in this
  /// theme's text color unless [color] says otherwise.
  TextStyle figureOf({
    double size = 13,
    FontWeight weight = FontWeight.w400,
    Color? color,
  }) => figureStyle(size: size, weight: weight, color: color ?? text);

  // --- instances -------------------------------------------------------

  /// Light theme (default): Banquise / Neige / Glacier.
  static final GerfautTokens light = GerfautTokens(
    background: const Color(0xFFF4F7F9),
    surface: const Color(0xFFFFFFFF),
    surfaceSunken: const Color(0xFFEBF0F4),
    border: const Color(0xFFC7D2DB),
    text: const Color(0xFF0D1317),
    textMuted: const Color(0xFF55636F),
    primary: const Color(0xFF0E7490),
    onPrimary: const Color(0xFFFFFFFF),
    alert: const Color(0xFFB3261E),
    alertSurface: const Color(0xFFFDE7E7),
    confirmed: const Color(0xFF116B41),
    confirmedSurface: const Color(0xFFDCF5E6),
    pending: const Color(0xFF745400),
    pendingSurface: const Color(0xFFFDF0CF),
    display: _display(const Color(0xFF0D1317)),
    h1: _h1(const Color(0xFF0D1317)),
    h2: _h2(const Color(0xFF0D1317)),
    body: _body(const Color(0xFF0D1317)),
    bodySmall: _bodySmall(const Color(0xFF0D1317)),
    label: _label(const Color(0xFF55636F)),
    amount: _amount(const Color(0xFF0D1317)),
    figure: figureStyle(color: const Color(0xFF0D1317)),
    data: _data(const Color(0xFF0D1317)),
  );

  /// Dark theme (option): Nuit polaire / Abysse / Glace.
  static final GerfautTokens dark = GerfautTokens(
    background: const Color(0xFF0B0F14),
    surface: const Color(0xFF161E27),
    surfaceSunken: const Color(0xFF1F2933),
    border: const Color(0xFF2A3440),
    text: const Color(0xFFE6ECF2),
    textMuted: const Color(0xFF8A98A6),
    primary: const Color(0xFF7DD3E8),
    onPrimary: const Color(0xFF06232B),
    alert: const Color(0xFFFF706D),
    alertSurface: const Color(0xFF161E27),
    confirmed: const Color(0xFF50B771),
    confirmedSurface: const Color(0xFF161E27),
    pending: const Color(0xFFC1983A),
    pendingSurface: const Color(0xFF161E27),
    display: _display(const Color(0xFFE6ECF2)),
    h1: _h1(const Color(0xFFE6ECF2)),
    h2: _h2(const Color(0xFFE6ECF2)),
    body: _body(const Color(0xFFE6ECF2)),
    bodySmall: _bodySmall(const Color(0xFFE6ECF2)),
    label: _label(const Color(0xFF8A98A6)),
    amount: _amount(const Color(0xFFE6ECF2)),
    figure: figureStyle(color: const Color(0xFFE6ECF2)),
    data: _data(const Color(0xFFE6ECF2)),
  );

  // --- style constructors ----------------------------------------------

  static TextStyle _bricolage({
    required double size,
    required double height,
    double? tracking,
    required Color color,
  }) {
    return TextStyle(
      fontFamily: GerfautFonts.display,
      fontSize: size,
      height: height,
      letterSpacing: tracking,
      color: color,
      fontWeight: FontWeight.w600,
      fontVariations: const [FontVariation('wght', 600)],
    );
  }

  static TextStyle _display(Color color) =>
      _bricolage(size: 32, height: 1.15, tracking: -0.64, color: color);

  static TextStyle _h1(Color color) =>
      _bricolage(size: 24, height: 1.25, tracking: -0.24, color: color);

  static TextStyle _h2(Color color) =>
      _bricolage(size: 18, height: 1.35, color: color);

  static TextStyle _body(Color color) {
    return TextStyle(
      fontFamily: GerfautFonts.ui,
      fontSize: 16,
      height: 1.55,
      color: color,
      fontWeight: FontWeight.w400,
      fontVariations: const [FontVariation('wght', 400)],
    );
  }

  static TextStyle _bodySmall(Color color) {
    return TextStyle(
      fontFamily: GerfautFonts.ui,
      fontSize: 14,
      height: 1.5,
      color: color,
      fontWeight: FontWeight.w400,
      fontVariations: const [FontVariation('wght', 400)],
    );
  }

  static TextStyle _label(Color color) {
    return TextStyle(
      fontFamily: GerfautFonts.ui,
      fontSize: 12,
      height: 1.4,
      letterSpacing: 0.48,
      color: color,
      fontWeight: FontWeight.w500,
      fontVariations: const [FontVariation('wght', 500)],
    );
  }

  /// Figures live in the UI face: amounts, fiat values, dates, block
  /// heights, sizes, counts, fee rates. Mono is kept for identifiers
  /// and code, where telling `0` from `O` is a security requirement.
  /// Tabular figures keep columns aligned and a value that updates from
  /// shifting the layout; the slight negative tracking stops long
  /// numbers from sprawling. The only place that feature list is set.
  static TextStyle figureStyle({
    double size = 13,
    FontWeight weight = FontWeight.w400,
    required Color color,
  }) {
    return TextStyle(
      fontFamily: GerfautFonts.ui,
      fontSize: size,
      height: size >= 24 ? 1.1 : 1.4,
      letterSpacing: -size * 0.01,
      color: color,
      fontWeight: weight,
      fontVariations: [FontVariation('wght', weight.value.toDouble())],
      fontFeatures: const [FontFeature.tabularFigures()],
    );
  }

  static TextStyle _amount(Color color) =>
      figureStyle(size: 32, weight: FontWeight.w600, color: color);

  static TextStyle _data(Color color) {
    return TextStyle(
      fontFamily: GerfautFonts.data,
      fontSize: 13,
      height: 1.6,
      color: color,
      fontWeight: FontWeight.w400,
      fontVariations: const [FontVariation('wght', 400)],
      fontFeatures: const [FontFeature.tabularFigures()],
    );
  }

  // --- ThemeExtension --------------------------------------------------

  @override
  GerfautTokens copyWith({
    Color? background,
    Color? surface,
    Color? surfaceSunken,
    Color? border,
    Color? text,
    Color? textMuted,
    Color? primary,
    Color? onPrimary,
    Color? alert,
    Color? alertSurface,
    Color? confirmed,
    Color? confirmedSurface,
    Color? pending,
    Color? pendingSurface,
    TextStyle? display,
    TextStyle? h1,
    TextStyle? h2,
    TextStyle? body,
    TextStyle? bodySmall,
    TextStyle? label,
    TextStyle? amount,
    TextStyle? figure,
    TextStyle? data,
  }) {
    return GerfautTokens(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceSunken: surfaceSunken ?? this.surfaceSunken,
      border: border ?? this.border,
      text: text ?? this.text,
      textMuted: textMuted ?? this.textMuted,
      primary: primary ?? this.primary,
      onPrimary: onPrimary ?? this.onPrimary,
      alert: alert ?? this.alert,
      alertSurface: alertSurface ?? this.alertSurface,
      confirmed: confirmed ?? this.confirmed,
      confirmedSurface: confirmedSurface ?? this.confirmedSurface,
      pending: pending ?? this.pending,
      pendingSurface: pendingSurface ?? this.pendingSurface,
      display: display ?? this.display,
      h1: h1 ?? this.h1,
      h2: h2 ?? this.h2,
      body: body ?? this.body,
      bodySmall: bodySmall ?? this.bodySmall,
      label: label ?? this.label,
      amount: amount ?? this.amount,
      figure: figure ?? this.figure,
      data: data ?? this.data,
    );
  }

  @override
  GerfautTokens lerp(GerfautTokens? other, double t) {
    if (other == null) return this;
    return GerfautTokens(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceSunken: Color.lerp(surfaceSunken, other.surfaceSunken, t)!,
      border: Color.lerp(border, other.border, t)!,
      text: Color.lerp(text, other.text, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      onPrimary: Color.lerp(onPrimary, other.onPrimary, t)!,
      alert: Color.lerp(alert, other.alert, t)!,
      alertSurface: Color.lerp(alertSurface, other.alertSurface, t)!,
      confirmed: Color.lerp(confirmed, other.confirmed, t)!,
      confirmedSurface: Color.lerp(confirmedSurface, other.confirmedSurface, t)!,
      pending: Color.lerp(pending, other.pending, t)!,
      pendingSurface: Color.lerp(pendingSurface, other.pendingSurface, t)!,
      display: TextStyle.lerp(display, other.display, t)!,
      h1: TextStyle.lerp(h1, other.h1, t)!,
      h2: TextStyle.lerp(h2, other.h2, t)!,
      body: TextStyle.lerp(body, other.body, t)!,
      bodySmall: TextStyle.lerp(bodySmall, other.bodySmall, t)!,
      label: TextStyle.lerp(label, other.label, t)!,
      amount: TextStyle.lerp(amount, other.amount, t)!,
      figure: TextStyle.lerp(figure, other.figure, t)!,
      data: TextStyle.lerp(data, other.data, t)!,
    );
  }
}
