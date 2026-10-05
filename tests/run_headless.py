"""Isolated offline NeoVim integration tests, identical locally and in CI."""

import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile


def main():
    root = Path(__file__).resolve().parent.parent
    texttools = Path(os.environ.get("TEXTTOOLS_ROOT") or Path.home() / "workspace/texttools")
    if not (texttools / ".venv/bin/pubble-send").is_file():
        sys.exit("Texttools ontbreekt: stel TEXTTOOLS_ROOT in en draai daar uv sync --locked.")
    nvim = os.environ.get("NVIM_BIN", "nvim")
    print(subprocess.check_output([nvim, "--version"], text=True).splitlines()[0], flush=True)
    tests = [root / "tests" / name for name in sys.argv[1:]] if sys.argv[1:] else sorted((root / "tests").glob("*.lua"))
    failed = []
    for test in tests:
        if test.parent != root / "tests" or test.suffix != ".lua" or not test.is_file():
            sys.exit(f"Ongeldig testbestand: {test}")
        print(f"Running tests/{test.name}", flush=True)
        with tempfile.TemporaryDirectory(prefix="nvim-headless-") as state:
            env = dict(os.environ)
            env.update({
                "TEXTTOOLS_ROOT": str(texttools.resolve()),
                "PUBBLE_TOKEN": "", "PUBBLE_DATADB": "", "OPENAI_API_KEY": "",
                "TEAMS_WEBHOOK_URL": "", "TEXTTOOLS_SOCIAL_POSTS": "legacy",
                "TEXTTOOLS_LOG_DIR": state + "/log",
                "TEXTTOOLS_SHARED_DIR": state + "/shared",
                "TEXTTOOLS_PUBLICATION_LINKS_FILE": state + "/links.yaml",
                "XDG_STATE_HOME": state + "/state", "XDG_CACHE_HOME": state + "/cache",
                "NVIM_LOG_FILE": state + "/nvim.log",
                "PYTHONPATH": str(root / "tests/offline"),
                "TEXTTOOLS_TEST_NETWORK_VIOLATIONS": state + "/network-violations",
            })
            process = subprocess.Popen([
                nvim, "--clean", "--headless", "-i", "NONE",
                "--cmd", f"set runtimepath^={root}", "-l", str(test),
            ], cwd=root, env=env, start_new_session=True)
            try:
                code = process.wait(timeout=60)
            except subprocess.TimeoutExpired:
                print(f"TIMEOUT: {test.name}", flush=True)
                code = 1
            finally:
                # Also reap subprocesses left behind by a failed assertion.
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                process.wait()
            if Path(env["TEXTTOOLS_TEST_NETWORK_VIOLATIONS"]).exists():
                print(f"FAIL: {test.name} probeerde extern netwerk te gebruiken", flush=True)
                code = 1
            if code:
                failed.append(test.name)
    print(f"\n{len(tests) - len(failed)}/{len(tests)} testbestanden geslaagd.", flush=True)
    if failed:
        print("Mislukt: " + ", ".join(failed), flush=True)
    return bool(failed)


if __name__ == "__main__":
    sys.exit(main())
