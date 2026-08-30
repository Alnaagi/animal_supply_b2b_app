import 'package:animal_supply_b2b/src/data/models/storefront_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StorefrontConfig', () {
    test('bundled default validates and matches schema v1', () {
      final config = StorefrontDefaults.bundled;
      expect(config.schemaVersion, storefrontConfigSchemaVersion);
      expect(() => config.validate(), returnsNormally);
      expect(config.sections.length, StorefrontSectionType.values.length);
    });

    test('round-trip json encode/decode preserves sections', () {
      final original = StorefrontDefaults.bundled.copyWith(
        theme: StorefrontDefaults.presetTheme(StorefrontThemePreset.modern),
        style: const StorefrontStyleConfig(cardRadius: 18, sectionSpacing: 16),
      );
      final decoded = StorefrontConfig.fromJson(original.toJson());
      expect(decoded.theme.preset, StorefrontThemePreset.modern);
      expect(decoded.style.cardRadius, 18);
      expect(decoded.sections.length, original.sections.length);
    });

    test('rejects duplicate sections', () {
      final broken = StorefrontDefaults.bundled.copyWith(
        sections: [
          ...StorefrontDefaults.bundled.sections,
          StorefrontDefaults.bundled.sections.first,
        ],
      );
      expect(() => broken.validate(), throwsFormatException);
    });

    test('detects low contrast warning', () {
      const lowContrast = StorefrontThemeConfig(
        textColor: Color(0xffdddddd),
        backgroundColor: Color(0xffeeeeee),
        cardColor: Color(0xfff5f5f5),
      );
      expect(lowContrast.hasLowTextContrast, isTrue);
    });

    test('best selling source is manual is_top_selling flag', () {
      expect(
        storefrontBestSellingSourceDoc,
        contains('is_top_selling'),
      );
    });
  });
}
