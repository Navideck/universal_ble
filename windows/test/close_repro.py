"""Launch a Flutter Windows app and check graceful close during startup."""

import argparse
import ctypes
import math
import subprocess
import time
from collections import Counter
from ctypes import wintypes


user32 = ctypes.WinDLL("user32", use_last_error=True)
user32.GetWindowThreadProcessId.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.DWORD)]
user32.GetClassNameW.argtypes = [wintypes.HWND, wintypes.LPWSTR, ctypes.c_int]
user32.PostMessageW.argtypes = [wintypes.HWND, wintypes.UINT, wintypes.WPARAM, wintypes.LPARAM]
enum_callback = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)
user32.EnumWindows.argtypes = [enum_callback, wintypes.LPARAM]


def find_window(pid):
    found = []

    @enum_callback
    def visit(hwnd, _):
        owner = wintypes.DWORD()
        user32.GetWindowThreadProcessId(hwnd, ctypes.byref(owner))
        name = ctypes.create_unicode_buffer(256)
        user32.GetClassNameW(hwnd, name, len(name))
        if owner.value == pid and name.value == "FLUTTER_RUNNER_WIN32_WINDOW":
            found.append(hwnd)
            return False
        return True

    user32.EnumWindows(visit, 0)
    return found[0] if found else None


def run_once(executable, delay):
    startup = subprocess.STARTUPINFO()
    startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
    startup.wShowWindow = 7  # SW_SHOWMINNOACTIVE
    start = time.monotonic()
    process = subprocess.Popen([executable], startupinfo=startup)
    posted = False
    try:
        while process.poll() is None and time.monotonic() - start < 30:
            if time.monotonic() - start >= delay:
                window = find_window(process.pid)
                if window:
                    if not user32.PostMessageW(window, 0x0010, 0, 0):
                        raise ctypes.WinError(ctypes.get_last_error())
                    posted = True
                    break
            time.sleep(0.01)
        code = process.wait(timeout=30)
        if not posted:
            return f"NO_WM_CLOSE:0x{code & 0xFFFFFFFF:08X}"
        return "0" if code == 0 else f"0x{code & 0xFFFFFFFF:08X}"
    except subprocess.TimeoutExpired:
        return "TIMEOUT"
    finally:
        if process.poll() is None:
            process.kill()
            process.wait()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("executable")
    parser.add_argument("--delays", default="0.5,1,2,8")
    parser.add_argument("--runs", type=int, default=10)
    args = parser.parse_args()
    if args.runs < 1:
        parser.error("--runs must be positive")
    try:
        delays = [float(value) for value in args.delays.split(",")]
    except ValueError:
        parser.error("--delays must be comma-separated numbers")
    if any(not math.isfinite(delay) or not 0 <= delay < 30 for delay in delays):
        parser.error("--delays must be finite values between 0 and 30 (exclusive)")
    failed = False
    for delay in delays:
        results = Counter()
        for _ in range(args.runs):
            results[run_once(args.executable, delay)] += 1
            time.sleep(0.1)
        print(f"{delay}s: {dict(results)}", flush=True)
        failed |= results["0"] != args.runs
    return int(failed)


if __name__ == "__main__":
    raise SystemExit(main())
