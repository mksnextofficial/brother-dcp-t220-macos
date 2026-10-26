#!/usr/bin/env python3
"""Exercise installer queue decisions with isolated command doubles, never CUPS."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]

class PackageTests(unittest.TestCase):
    def run_case(self, connected=True, existing=False, ours=True, same=True, fail=False):
        with tempfile.TemporaryDirectory() as tmp:
            t = Path(tmp)
            driver = t / 'driver'
            driver.mkdir()
            ppds = t / 'ppds'
            ppds.mkdir()
            (ppds / 'Brother_PWG.ppd').write_text(str(driver / 'rastertobrotherpjl') if ours else 'other')
            mock = t / 'mock'
            mock.mkdir()
            uri = 'usb://Brother/DCP-T220?serial=TEST'
            commands = {
                'lpinfo': f"echo 'direct {uri}'" if connected else "echo 'direct usb://Brother/OTHER?serial=TEST'",
                'lpstat': f'''if [ "$1" = -p ]; then exit {0 if existing else 1}; fi
printf '%s\\n' 'device for Brother_PWG: {uri if same else 'usb://Brother/DCP-T220?serial=DIFFERENT'}' ''',
                'lpadmin': f'''printf '%s\\n' "$@" >> '{t}/calls'
exit {1 if fail else 0}''',
            }
            for name, body in commands.items():
                f = mock / name
                f.write_text('#!/bin/bash\n' + body + '\n')
                f.chmod(0o755)
            script = (ROOT / 'packaging/scripts/postinstall').read_text()
            script = script.replace('export PATH=/usr/bin:/bin:/usr/sbin:/sbin', f'export PATH={mock}:/usr/bin:/bin:/usr/sbin:/sbin')
            script = script.replace('/Library/Printers/BrotherPWG', str(driver)).replace('/etc/cups/ppd', str(ppds))
            result = subprocess.run(['/bin/bash', '-c', script], capture_output=True, text=True)
            calls = (t/'calls').read_text() if (t/'calls').exists() else ''
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertNotIn('-x\n', calls)
            return calls, result.stdout + result.stderr

    def test_connected_creates(self):
        self.assertIn('-p\nBrother_PWG\n', self.run_case()[0])
    def test_disconnected_installs_without_queue(self):
        self.assertEqual(self.run_case(connected=False)[0], '')
    def test_own_queue_updated_without_delete(self):
        self.assertIn('-p\n', self.run_case(existing=True)[0])
    def test_unrelated_queue_preserved(self):
        self.assertEqual(self.run_case(existing=True, ours=False)[0], '')
    def test_other_printer_serial_preserved(self):
        self.assertEqual(self.run_case(existing=True, same=False)[0], '')
    def test_queue_failure_explains_manual_setup(self):
        self.assertIn('automatic queue setup failed', self.run_case(fail=True)[1])
    def test_distribution(self):
        tree = ET.parse(ROOT/'packaging/Distribution.xml')
        self.assertEqual(tree.find('.//os-version').attrib['min'], '27.0')
        self.assertEqual(tree.find('domains').attrib['enable_anywhere'], 'false')
    def test_quality_labels_keep_protocol_keys(self):
        s = (ROOT/'ppd/template.ppd').read_text()
        self.assertIn('*BRQuality Draft/EcoMode (Draft)', s)
        self.assertIn('*BRQuality Best/Fine (Best)', s)

if __name__ == '__main__':
    unittest.main(verbosity=2)
