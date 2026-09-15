import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/app.dart';
import 'package:gerfaut/theme/tokens.dart';

void main() {
  test('both token sets exist and differ where the theme changes', () {
    final light = GerfautTokens.light;
    final dark = GerfautTokens.dark;

    expect(light.background, isNot(dark.background));
    expect(light.surface, isNot(dark.surface));
    expect(light.text, isNot(dark.text));
    expect(light.primary, isNot(dark.primary));
    expect(light.onPrimary, isNot(dark.onPrimary));
    expect(light.alert, isNot(dark.alert));
    expect(light.confirmed, isNot(dark.confirmed));
    expect(light.pending, isNot(dark.pending));
    expect(light.premium, isNot(dark.premium));
    expect(light.onPremium, isNot(dark.onPremium));
  });

  test('the premium ink reads on its own surfaces in both themes', () {
    // WCAG 2.x: 4.5:1 for text, 3:1 for a control's edge.
    double ratio(Color a, Color b) {
      final la = a.computeLuminance();
      final lb = b.computeLuminance();
      final (hi, lo) = la > lb ? (la, lb) : (lb, la);
      return (hi + 0.05) / (lo + 0.05);
    }

    for (final tokens in [GerfautTokens.light, GerfautTokens.dark]) {
      // The filled button's label.
      expect(ratio(tokens.premium, tokens.onPremium), greaterThan(4.5));
      // A card icon, a focus ring, a switch track, on what they sit on.
      expect(ratio(tokens.premium, tokens.surface), greaterThan(3));
      expect(ratio(tokens.premium, tokens.surfaceSunken), greaterThan(3));
      expect(ratio(tokens.premium, tokens.background), greaterThan(3));
      // The pill's word on its own surface.
      expect(ratio(tokens.premium, tokens.premiumSurface), greaterThan(4.5));
    }
  });

  test('type roles keep their families and tabular figures', () {
    for (final tokens in [GerfautTokens.light, GerfautTokens.dark]) {
      expect(tokens.display.fontFamily, GerfautFonts.display);
      expect(tokens.h1.fontFamily, GerfautFonts.display);
      expect(tokens.h2.fontFamily, GerfautFonts.display);
      expect(tokens.body.fontFamily, GerfautFonts.ui);
      expect(tokens.bodySmall.fontFamily, GerfautFonts.ui);
      expect(tokens.label.fontFamily, GerfautFonts.ui);
      // Figures sit in the UI face; mono is left to identifiers.
      expect(tokens.amount.fontFamily, GerfautFonts.ui);
      expect(tokens.figure.fontFamily, GerfautFonts.ui);
      expect(tokens.figureOf(size: 11).fontFamily, GerfautFonts.ui);
      expect(tokens.data.fontFamily, GerfautFonts.data);

      // Every figure and datum aligns: tabular figures throughout.
      for (final style in [
        tokens.amount,
        tokens.figure,
        tokens.figureOf(size: 11, weight: FontWeight.w500),
        tokens.data,
      ]) {
        expect(
          style.fontFeatures,
          contains(const FontFeature.tabularFigures()),
        );
      }

      // Large figures carry the slight negative tracking.
      expect(tokens.amount.letterSpacing, lessThan(0));
      expect(tokens.figure.letterSpacing, lessThan(0));
      expect(tokens.amount.fontWeight, FontWeight.w600);
      expect(
        tokens.figureOf(weight: FontWeight.w500).fontVariations,
        contains(const FontVariation('wght', 500)),
      );
    }
  });

  test('both built themes carry the tokens extension', () {
    final light = themeFrom(GerfautTokens.light, Brightness.light);
    final dark = themeFrom(GerfautTokens.dark, Brightness.dark);

    expect(light.extension<GerfautTokens>(), same(GerfautTokens.light));
    expect(dark.extension<GerfautTokens>(), same(GerfautTokens.dark));
    expect(light.scaffoldBackgroundColor, GerfautTokens.light.background);
    expect(dark.scaffoldBackgroundColor, GerfautTokens.dark.background);
    expect(light.brightness, Brightness.light);
    expect(dark.brightness, Brightness.dark);
  });

  test('bottom sheets take the card surface and the sheet radius', () {
    for (final (tokens, brightness) in [
      (GerfautTokens.light, Brightness.light),
      (GerfautTokens.dark, Brightness.dark),
    ]) {
      final sheet = themeFrom(tokens, brightness).bottomSheetTheme;
      expect(sheet.backgroundColor, tokens.surface);
      expect(sheet.surfaceTintColor, Colors.transparent);
      expect(
        (sheet.shape! as RoundedRectangleBorder).borderRadius,
        const BorderRadius.vertical(top: Radius.circular(GerfautRadius.canvas)),
      );
    }
  });
}
