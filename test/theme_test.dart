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
  });

  test('type roles keep their families and tabular figures', () {
    for (final tokens in [GerfautTokens.light, GerfautTokens.dark]) {
      expect(tokens.display.fontFamily, GerfautFonts.display);
      expect(tokens.h1.fontFamily, GerfautFonts.display);
      expect(tokens.h2.fontFamily, GerfautFonts.display);
      expect(tokens.body.fontFamily, GerfautFonts.ui);
      expect(tokens.bodySmall.fontFamily, GerfautFonts.ui);
      expect(tokens.label.fontFamily, GerfautFonts.ui);
      expect(tokens.amount.fontFamily, GerfautFonts.data);
      expect(tokens.data.fontFamily, GerfautFonts.data);

      // Every Bitcoin datum aligns: tabular figures on the mono styles.
      expect(
        tokens.amount.fontFeatures,
        contains(const FontFeature.tabularFigures()),
      );
      expect(
        tokens.data.fontFeatures,
        contains(const FontFeature.tabularFigures()),
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
}
