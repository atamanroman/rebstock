"""Offline checks for the local invoice-import helpers.

Run: python3 -m unittest discover -s test -p 'invoice_skill_test.py'
"""

import contextlib
from email.message import EmailMessage
import importlib.util
import io
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


SCRIPTS = Path(__file__).resolve().parents[1] / ".agents/skills/importing-wine-invoices/scripts"


def load_helper(name):
    spec = importlib.util.spec_from_file_location(name, SCRIPTS / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


parse_eml = load_helper("parse_eml")
vivino = load_helper("vivino")


class InvoiceSkillTests(unittest.TestCase):
    def parse_message(self, message):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "invoice.eml"
            path.write_bytes(message.as_bytes())
            output = io.StringIO()
            with patch("sys.argv", ["parse_eml.py", str(path)]), contextlib.redirect_stdout(output):
                self.assertEqual(parse_eml.main(), 0)
            return output.getvalue()

    def test_html_line_items_are_kept_alongside_plain_text(self):
        message = EmailMessage()
        message["Subject"] = "Invoice 37140"
        message.set_content("Thank you for your order. See the invoice below.")
        message.add_alternative(
            "<table><tr><td>Riesling 2023</td><td>2</td><td>14.50 €</td></tr></table>",
            subtype="html",
        )
        text = self.parse_message(message)
        self.assertIn("Thank you for your order", text)
        self.assertIn("Riesling 2023\t2\t14.50 €", text)
        self.assertIn("HTML alternative (same invoice)", text)

    def test_original_email_charset_is_respected(self):
        message = EmailMessage()
        message.set_content("<p>Müller-Thurgau</p>", subtype="html", charset="iso-8859-1")
        self.assertIn("Müller-Thurgau", self.parse_message(message))

    def test_text_attachments_are_not_invoice_body_alternatives(self):
        message = EmailMessage()
        message.set_content("Invoice body")
        message.add_attachment("Unrelated attachment", filename="notes.txt")
        text = self.parse_message(message)
        self.assertIn("Invoice body", text)
        self.assertNotIn("Unrelated attachment", text)
        self.assertIn("Attachment (inspect separately): notes.txt", text)

    def test_html_table_boundaries_and_entities_survive(self):
        text = parse_eml.readable_text(
            "<style>hidden</style><script>hidden</script>"
            "<table><tr><td>A &amp; B</td><td>2</td></tr><tr><td>C</td><td>3</td></tr></table>"
        )
        self.assertEqual(text, "A & B\t2\nC\t3\n")

    def test_discovery_types_use_import_enums_without_guessing_red(self):
        expected = {1: "RED", 2: "WHITE", 3: "SPARKLING", 4: "ROSE", 7: "DESSERT",
                    24: "OTHER", 999: "OTHER", None: "OTHER"}
        for type_id, wine_type in expected.items():
            with self.subTest(type_id=type_id):
                result = vivino.summarize({"id": 1, "name": "Example", "type_id": type_id})
                self.assertEqual(result["wine_type"], wine_type)
                self.assertEqual(result["type_id"], type_id)

    def test_discovery_prefers_locale_stable_country_codes(self):
        result = vivino.summarize({
            "id": 1, "name": "Example",
            "region": {"country": {"code": "GE", "name": "Georgien"}},
        })
        self.assertEqual(result["country"], "GE")


if __name__ == "__main__":
    unittest.main()
