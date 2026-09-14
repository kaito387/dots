"""Regression tests: real temporary files, mocked network and system changes."""
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import tempfile
import unittest


REPO = Path(__file__).resolve().parents[1]


class BootstrapTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="dots-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def run_bash(self, body, expected=0):
        script = f"""
source {shlex.quote(str(REPO / 'bootstrap.sh'))}
TARGET_HOME={shlex.quote(str(self.root))}
unset ZSH_CUSTOM ZDOTDIR
id() {{
  case "$1" in
    -u) echo 1000 ;;
    -un) echo dots-test ;;
    *) command id "$@" ;;
  esac
}}
sudo() {{ echo 'Unexpected sudo' >&2; return 97; }}
curl() {{ echo 'Unexpected curl' >&2; return 97; }}
git() {{ echo 'Unexpected git' >&2; return 97; }}
chsh() {{ echo 'Unexpected chsh' >&2; return 97; }}
{body}
"""
        result = subprocess.run(["bash", "-c", script], capture_output=True, text=True)
        self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
        return result

    def test_deployment_is_complete_and_repeatable(self):
        self.run_bash("main --link-only\nmain --link-only")
        for target, source in {
            ".zshrc": "zsh/zshrc",
            ".p10k.zsh": "zsh/p10k.zsh",
            ".tmux.conf": "tmux/tmux.conf",
            ".tmux/clipboard-copy.sh": "tmux/clipboard-copy.sh",
        }.items():
            path = self.root / target
            self.assertTrue(path.is_symlink())
            self.assertEqual(path.resolve(), REPO / source)
        self.assertEqual(list(self.root.rglob("*.backup.*")), [])

    def test_conflicts_preserve_every_backup(self):
        target = self.root / ".zshrc"
        target.write_text("first")
        (self.root / ".zshrc.bak").write_text("legacy")
        self.run_bash("main --link-only")
        target.unlink()
        target.write_text("second")
        self.run_bash("main --link-only")
        saved = [p.read_text() for p in self.root.glob(".zshrc.backup.*/original")]
        self.assertCountEqual(saved, ["first", "second"])
        self.assertEqual((self.root / ".zshrc.bak").read_text(), "legacy")

    def test_directory_and_broken_symlink_are_preserved(self):
        (self.root / ".zshrc").mkdir()
        (self.root / ".zshrc" / "personal").write_text("keep")
        (self.root / ".p10k.zsh").symlink_to("nonexistent")
        self.run_bash("main --link-only")
        backup = next(self.root.glob(".zshrc.backup.*/original/personal"))
        self.assertEqual(backup.read_text(), "keep")
        backup = next(self.root.glob(".p10k.zsh.backup.*/original"))
        self.assertTrue(backup.is_symlink())
        self.assertEqual(os.readlink(backup), "nonexistent")

    def test_link_failure_restores_original(self):
        (self.root / ".zshrc").write_text("keep")
        self.run_bash('ln() { return 1; }\nmain --link-only', expected=1)
        self.assertEqual((self.root / ".zshrc").read_text(), "keep")
        self.assertFalse((self.root / ".zshrc").is_symlink())

    def test_missing_source_stops_before_deployment(self):
        (self.root / ".zshrc").write_text("keep")
        self.run_bash('CONFIG_SOURCES+=(missing)\nmain --link-only', expected=1)
        self.assertEqual((self.root / ".zshrc").read_text(), "keep")
        self.assertEqual(list(self.root.glob("*.backup.*")), [])

    def test_download_failure_does_not_execute_partial_script(self):
        result = self.run_bash('''
curl() { printf 'touch "%s/executed"\n' "$TARGET_HOME" > "${@: -1}"; return 22; }
install_omz
''', expected=22)
        self.assertFalse((self.root / "executed").exists())
        self.assertNotIn("Oh My Zsh installed.", result.stdout)

    def test_empty_download_is_rejected(self):
        self.run_bash('curl() { return 0; }\ninstall_omz', expected=1)

    def test_installer_failure_propagates(self):
        self.run_bash('''
curl() { printf 'exit 23\n' > "${@: -1}"; }
install_omz
''', expected=23)

    def test_omz_preserves_user_zshrc_and_verifies_installation(self):
        (self.root / ".zshrc").write_text("keep")
        self.run_bash('''
curl() {
  cat > "${@: -1}" <<'EOF'
set -eu
[ "$KEEP_ZSHRC" = yes ] && [ "$CHSH" = no ] && [ "$RUNZSH" = no ]
mkdir -p "$ZSH"
touch "$ZSH/oh-my-zsh.sh"
EOF
}
install_omz
install_omz
''')
        self.assertEqual((self.root / ".zshrc").read_text(), "keep")

    def test_omz_rejects_success_without_installed_files(self):
        self.run_bash('''
curl() { printf 'exit 0\n' > "${@: -1}"; }
install_omz
''', expected=1)

    def test_chsh_failure_never_reports_success(self):
        result = self.run_bash('''
SHELL=/not-zsh
zsh() { :; }
chsh() { return 1; }
set_default_shell_to_zsh
''', expected=1)
        self.assertNotIn("Default shell set to zsh", result.stdout)

    def test_apt_update_failure_prevents_install(self):
        self.run_bash('''
need_cmd() { [[ "$1" = apt-get ]]; }
sudo() {
  if [[ "$2" = update ]]; then return 42; fi
  touch "$TARGET_HOME/unexpected-install"
}
if install_pkg zoxide; then exit 99; else exit "$?"; fi
''', expected=42)
        self.assertFalse((self.root / "unexpected-install").exists())

    def test_zoxide_fallback_is_found_in_local_bin(self):
        self.run_bash('''
need_cmd() { [[ "$1" = zoxide && -x "$TARGET_HOME/.local/bin/zoxide" ]]; }
install_pkg() { return 1; }
run_install_script() {
  mkdir -p "$TARGET_HOME/.local/bin"
  printf '#!/bin/sh\necho zoxide-test\n' > "$TARGET_HOME/.local/bin/zoxide"
  chmod +x "$TARGET_HOME/.local/bin/zoxide"
}
install_zoxide
''')

    @unittest.skipUnless(shutil.which("gpg"), "gpg unavailable")
    def test_eza_repo_retry_and_failed_download_preserve_keyring(self):
        (self.root / "gnupg").mkdir(mode=0o700)
        raw = self.root / "key-data"
        raw.write_bytes(b"test keyring payload")
        subprocess.run([
            "gpg", "--homedir", str(self.root / "gnupg"), "--enarmor",
            "--output", str(self.root / "key.asc"), str(raw)
        ], check=True, capture_output=True)
        (self.root / "etc/apt/sources.list.d").mkdir(parents=True)
        self.run_bash('''
curl() { cp "$TARGET_HOME/key.asc" "${@: -1}"; }
gpg() { command gpg --homedir "$TARGET_HOME/gnupg" "$@"; }
sudo() {
  [[ "$1" = install ]] || return 97
  shift
  local arg args=()
  for arg in "$@"; do
    case "$arg" in /etc/*) arg="$TARGET_HOME$arg" ;; esac
    args+=("$arg")
  done
  command install "${args[@]}"
}
configure_eza_repo
configure_eza_repo
curl() { return 22; }
if configure_eza_repo; then exit 99; fi
''')
        self.assertEqual((self.root / "etc/apt/keyrings/gierens.gpg").read_bytes(), raw.read_bytes())

    def test_check_is_read_only_and_fails_for_missing_config(self):
        self.run_bash("main --check", expected=1)
        self.assertEqual(list(self.root.iterdir()), [])

    def test_install_only_does_not_deploy(self):
        self.run_bash('install_dependencies() { :; }\nmain --install')
        self.assertEqual(list(self.root.iterdir()), [])

    def test_invalid_modes_fail_before_mutation(self):
        for args in ("--check --chsh", "--install --link-only", "--typo"):
            with self.subTest(args=args):
                self.run_bash("main " + args, expected=2)
        self.assertEqual(list(self.root.iterdir()), [])

    def test_root_is_rejected_before_any_install_or_deploy(self):
        for mode in ("", "--install", "--link-only", "--check", "--chsh"):
            with self.subTest(mode=mode):
                result = self.run_bash('''
id() { case "$1" in -u) echo 0 ;; -un) echo root ;; esac; }
export SUDO_USER=lht
install_dependencies() { touch "$TARGET_HOME/unexpected-install"; }
main ''' + mode, expected=1)
                self.assertIn("Do not run bootstrap as root", result.stderr)
                self.assertNotIn("Configs deployed", result.stdout)
        self.assertEqual(list(self.root.iterdir()), [])

    def test_non_root_with_sudo_environment_can_deploy(self):
        result = self.run_bash('export SUDO_USER=root\nmain --link-only')
        self.assertIn("Target user: dots-test (uid 1000)", result.stdout)
        self.assertIn("The login shell was not changed", result.stdout)
        self.assertTrue((self.root / ".zshrc").is_symlink())

    def test_non_root_with_missing_home_is_rejected(self):
        self.run_bash('TARGET_HOME="$TARGET_HOME/missing"\nmain --link-only', expected=1)
        self.assertEqual(list(self.root.iterdir()), [])

    @unittest.skipIf(os.geteuid() == 0, "requires an unprivileged user")
    def test_non_root_with_foreign_home_is_rejected(self):
        result = self.run_bash('TARGET_HOME=/root\nmain --link-only', expected=1)
        self.assertIn("Home directory must", result.stderr)

    def test_redirected_zdotdir_is_rejected_before_deployment(self):
        result = self.run_bash('export ZDOTDIR="$TARGET_HOME/elsewhere"\nmain --link-only', expected=1)
        self.assertIn("Zsh would not load", result.stderr)
        self.assertEqual(list(self.root.iterdir()), [])

    def test_help_is_available_as_root(self):
        result = self.run_bash('id() { echo 0; }\nmain --help')
        self.assertIn("Usage:", result.stdout)
        self.assertEqual(list(self.root.iterdir()), [])


class ClipboardTests(unittest.TestCase):
    def test_preserves_trailing_newlines_and_stops_on_tmux_failure(self):
        with tempfile.TemporaryDirectory(prefix="dots-clipboard-") as tmp:
            root = Path(tmp)
            commands = {
                "tmux": '#!/bin/sh\n[ -z "${FAIL_TMUX:-}" ] || exit 4\nprintf "hello\\n\\n" > "$2"\n',
                "wl-copy": '#!/bin/sh\ncat > "$CLIPBOARD_OUT"\n',
            }
            for name, content in commands.items():
                path = root / name
                path.write_text(content)
                path.chmod(0o755)
            output = root / "clipboard"
            env = dict(os.environ, PATH=tmp + os.pathsep + os.environ["PATH"],
                       WAYLAND_DISPLAY="test", CLIPBOARD_OUT=str(output))
            subprocess.run(["sh", str(REPO / "tmux/clipboard-copy.sh")], env=env, check=True)
            self.assertEqual(output.read_bytes(), b"hello\n\n")
            output.unlink()
            result = subprocess.run(["sh", str(REPO / "tmux/clipboard-copy.sh")],
                                    env=dict(env, FAIL_TMUX="1"))
            self.assertEqual(result.returncode, 4)
            self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main()
