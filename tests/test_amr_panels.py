"""The shipped AST panels stay in step with the CPHL panel catalog."""
import csv
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1] / "configs/configuration/backend"


def catalog_panels():
    rows = csv.DictReader(line for line in (ROOT / "panels/png-panels.csv").open() if not line.startswith("#"))
    return {row["panelName"]: row["tests"].split("|") for row in rows if row["panelName"].upper().startswith("AST")}


def configured_panels():
    panels = {}
    for row in csv.DictReader((ROOT / "microbiology-ast-panels/png-ast-panels.csv").open()):
        panels.setdefault(row["panelName"], []).append(row)
    return panels


class AstPanelConfigurationTest(unittest.TestCase):
    def test_default_standard_matches_its_pinned_package_version(self):
        with (ROOT / "microbiology-settings/png-amr.csv").open() as source:
            settings = {row["name"]: row["value"] for row in csv.DictReader(source)}
        authority = settings["microbiologyDefaultBreakpointAuthority"].lower()
        pin_path = ROOT.parents[1] / "configuration-packages" / ("amr-reference-" + authority + ".json")
        pin = json.loads(pin_path.read_text())
        edition = settings["microbiologyDefaultBreakpointVersion"]
        self.assertTrue(edition.endswith("-" + pin["version"]),
                        "The default edition must be supplied by the pinned reference package")

    def test_every_catalog_ast_panel_is_configured_with_its_drugs(self):
        catalog, configured = catalog_panels(), configured_panels()
        self.assertEqual(set(catalog), set(configured))
        for name, tests in catalog.items():
            # "Ceftriaxone CRO" (disk) and "CRO E-test MIC" are one drug; a run picks the technique.
            drugs = {t.split()[0] if "E-test" in t else t.split()[-1] for t in tests if "Zone Diameter" not in t}
            with self.subTest(panel=name):
                self.assertEqual(len(drugs), len(configured[name]))

    def test_disk_content_belongs_to_disk_drugs_only(self):
        for name, rows in configured_panels().items():
            etest = "E-test" in name
            for row in rows:
                with self.subTest(panel=name, drug=row["antibioticWhonetCode"]):
                    self.assertEqual(row["antibioticWhonetCode"], row["antibioticWhonetCode"].strip().upper())
                    if etest:
                        self.assertEqual("", row["diskContent"])

    def test_panel_level_columns_agree_within_a_panel(self):
        for name, rows in configured_panels().items():
            for column in ("susceptibilityProtocol", "defaultFor"):
                values = {row[column] for row in rows if row[column]}
                with self.subTest(panel=name, column=column):
                    self.assertLessEqual(len(values), 1)


if __name__ == "__main__":
    unittest.main()
