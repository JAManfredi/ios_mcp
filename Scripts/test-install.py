"""Exercise make install without changing host packages or compiling Swift."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


class InstallTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="ios-mcp-install-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        shutil.copyfile(Path(__file__).resolve().parents[1] / "Makefile", self.root / "Makefile")
        self.commands = self.root / "commands"
        self.commands.mkdir()
        self.destination = self.root / "install prefix" / "bin" / "ios-mcp"
        self.destination.parent.mkdir(parents=True)
        self.destination.write_text("previous executable\n")
        self.env = dict(os.environ, PATH=f"{self.commands}:/usr/bin:/bin",
                        INSTALL_CHECK_LOG=str(self.root / "commands.log"),
                        INSTALL_CHECK_BIN=str(self.root / "build products"))
        self.stub("brew", '''
printf 'brew %s\n' "$*" >> "$INSTALL_CHECK_LOG"
test "$*" = 'install cameroncooke/axe/axe' || exit 99
exit "${INSTALL_CHECK_BREW_STATUS:-0}"
''')
        self.stub("swift", '''
printf 'swift %s\n' "$*" >> "$INSTALL_CHECK_LOG"
if [ "$*" = 'build -c release --show-bin-path' ]; then
    printf '%s\n' "$INSTALL_CHECK_BIN"
    exit "${INSTALL_CHECK_PATH_STATUS:-0}"
fi
test "$*" = 'build -c release --disable-sandbox' || exit 99
test "${INSTALL_CHECK_BUILD_STATUS:-0}" = 0 || exit 1
mkdir -p "$INSTALL_CHECK_BIN"
printf '#!/bin/sh\necho installed\n' > "$INSTALL_CHECK_BIN/ios-mcp"
''')

    def stub(self, name, body):
        path = self.commands / name
        path.write_text("#!/bin/sh\nset -eu\n" + body)
        path.chmod(0o755)

    def install(self, **env):
        return subprocess.run(
            ["/usr/bin/make", "install", f"PREFIX={self.destination.parent.parent}"],
            cwd=self.root, env=self.env | env, capture_output=True, text=True,
        )

    def test_installs_dependency_and_resolved_binary(self):
        result = self.install()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(subprocess.check_output([self.destination], text=True), "installed\n")
        self.assertEqual((self.root / "commands.log").read_text().splitlines()[0],
                         "brew install cameroncooke/axe/axe")

    def test_failures_preserve_existing_install(self):
        for failure in ("BREW", "BUILD", "PATH"):
            with self.subTest(failure=failure):
                result = self.install(**{f"INSTALL_CHECK_{failure}_STATUS": "1"})
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(self.destination.read_text(), "previous executable\n")


if __name__ == "__main__":
    unittest.main()
