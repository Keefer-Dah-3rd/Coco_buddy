"""Tests for the token generator.  Run:  python3 -m unittest discover -s scripts/tokens"""

import copy
import json
import unittest

import generate_swift as gen


class GeneratorTests(unittest.TestCase):
    def setUp(self):
        self.tokens = json.loads(gen.TOKENS.read_text())

    def test_repository_tokens_are_valid_and_generated_file_is_current(self):
        swift = gen.generate(self.tokens)
        self.assertEqual(gen.OUTPUT.read_text(), swift,
                         "DesignTokens.generated.swift is stale — run scripts/tokens/generate_swift.py")

    # Expectations are read from tokens.json, so a design change synced from Figma doesn't break them.
    def hex_of(self, reference):
        value = self.tokens["primitives"].get(reference, reference)
        return "0x" + value[1:].upper()

    def test_light_and_dark_colors_resolve_through_primitives(self):
        swift = gen.generate(self.tokens)
        paper = self.tokens["color"]["surface/paper"]
        self.assertIn(f"static let paper = dynamic(light: {self.hex_of(paper['light'])}, dark: {self.hex_of(paper['dark'])})", swift)
        on_accent = self.tokens["color"]["accent/on-accent"]
        self.assertEqual(on_accent["light"], on_accent["dark"])
        self.assertIn(f"static let onAccent = Color(hex: {self.hex_of(on_accent['light'])})", swift)

    def test_brand_aliases_resolve(self):
        swift = gen.generate(self.tokens)
        tag = self.tokens["brand"]["coco/tag-light"]["value"]
        self.assertIn(tag, self.tokens["primitives"], "coco/tag-light should alias a primitive")
        self.assertIn(f"static let accent = NSColor(hex: {self.hex_of(tag)})", swift)

    def test_type_styles_carry_tracking_and_case(self):
        tokens = copy.deepcopy(self.tokens)
        tokens["typography"]["Mono/Label"] = {"swift": "monoLabel", "family": "mono", "weight": "semibold", "size": 10, "tracking": 0.8, "uppercase": True}
        tokens["typography"]["Body/Default"] = {"swift": "body", "family": "sans", "weight": "regular", "size": 13}
        swift = gen.generate(tokens)
        self.assertIn("static let monoLabel = TypeStyle(design: .monospaced, weight: .semibold, size: 10, "
                      "tracking: 0.8, uppercase: true)", swift)
        self.assertIn("static let body = TypeStyle(design: .default, weight: .regular, size: 13)", swift)

    def test_changing_a_primitive_changes_every_semantic_color_that_uses_it(self):
        tokens = copy.deepcopy(self.tokens)
        tokens["primitives"]["orange/500"] = "#123456"
        swift = gen.generate(tokens)
        dark = self.hex_of(tokens["color"]["accent/default"]["dark"])
        self.assertIn(f"static let accent = dynamic(light: 0x123456, dark: {dark})", swift)
        self.assertIn("static let accent = NSColor(hex: 0x123456)", swift)

    def test_rejects_an_unknown_alias(self):
        tokens = copy.deepcopy(self.tokens)
        tokens["color"]["surface/paper"]["light"] = "sand/999"
        with self.assertRaisesRegex(gen.TokenError, "sand/999"):
            gen.generate(tokens)

    def test_rejects_duplicate_swift_names(self):
        tokens = copy.deepcopy(self.tokens)
        tokens["space"]["huge"] = {"swift": "xl", "value": 40}
        with self.assertRaisesRegex(gen.TokenError, "also used by"):
            gen.generate(tokens)

    def test_rejects_bad_hex_and_weights(self):
        tokens = copy.deepcopy(self.tokens)
        tokens["primitives"]["sand/50"] = "F3F1EC"
        tokens["typography"]["Caption"]["weight"] = "Semi Bold"
        with self.assertRaises(gen.TokenError) as raised:
            gen.generate(tokens)
        self.assertIn("sand/50", str(raised.exception))
        self.assertIn("Caption", str(raised.exception))


if __name__ == "__main__":
    unittest.main()
