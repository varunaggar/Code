#!/usr/bin/env python3
import argparse
import threading
import time
import sys

try:
    from pynput import mouse, keyboard
except Exception as e:
    print("pynput is required. Install with: pip install pynput", file=sys.stderr)
    raise


class AutoClicker:
    def __init__(self, interval: float, count: int, button: str = "left"):
        self.interval = max(0.001, float(interval))
        self.count = int(count)
        self.button = {
            "left": mouse.Button.left,
            "right": mouse.Button.right,
            "middle": mouse.Button.middle,
        }.get(button.lower(), mouse.Button.left)

        self._mouse = mouse.Controller()
        self._worker: threading.Thread | None = None
        self._stop_event = threading.Event()
        self._run_lock = threading.Lock()
        self._is_running = False

    def is_running(self) -> bool:
        return self._is_running

    def start(self):
        with self._run_lock:
            if self._is_running:
                return
            self._stop_event.clear()
            self._worker = threading.Thread(target=self._run, name="autoclicker", daemon=True)
            self._is_running = True
            self._worker.start()

    def stop(self):
        with self._run_lock:
            if not self._is_running:
                return
            self._stop_event.set()
            if self._worker and self._worker.is_alive():
                self._worker.join(timeout=2)
            self._is_running = False

    def _run(self):
        try:
            remaining = self.count
            while not self._stop_event.is_set():
                # Perform one click (press + release)
                self._mouse.press(self.button)
                self._mouse.release(self.button)

                if remaining > 0:
                    remaining -= 1
                    if remaining == 0:
                        break

                # Sleep in small chunks to be responsive to stop
                end_time = time.time() + self.interval
                while not self._stop_event.is_set() and time.time() < end_time:
                    time.sleep(min(0.01, max(0.0, end_time - time.time())))
        finally:
            with self._run_lock:
                self._is_running = False


def parse_args():
    p = argparse.ArgumentParser(
        description="Simple macOS auto-clicker with global hotkeys (requires Accessibility permissions)",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    start_group = p.add_mutually_exclusive_group()
    start_group.add_argument(
        "--start-delay", type=float, default=0.0,
        help="Delay in seconds before starting after pressing the start hotkey"
    )
    start_group.add_argument(
        "--start-after-click", action="store_true",
        help="After pressing the start hotkey, begin only after the next physical mouse click"
    )
    p.add_argument(
        "--interval", type=float, default=0.1,
        help="Delay in seconds between clicks"
    )
    p.add_argument(
        "--count", type=int, default=0,
        help="How many clicks to perform (0 = infinite until stopped)"
    )
    p.add_argument(
        "--button", choices=["left", "right", "middle"], default="left",
        help="Mouse button to click"
    )
    p.add_argument(
        "--hotkey-start", default="<cmd>+<alt>+s",
        help="Global hotkey to start (pynput format, e.g. '<cmd>+<alt>+s')"
    )
    p.add_argument(
        "--hotkey-stop", default="<cmd>+<alt>+x",
        help="Global hotkey to stop (pynput format, e.g. '<cmd>+<alt>+x')"
    )
    p.add_argument(
        "--verbose", action="store_true",
        help="Verbose logging"
    )
    return p.parse_args()


def wait_for_next_physical_click(verbose: bool = False):
    done = threading.Event()

    def on_click(x, y, button, pressed):
        # Trigger on the first press event
        if pressed:
            if verbose:
                print(f"Detected first click at ({x},{y}); starting...", flush=True)
            done.set()
            return False  # stop listener
        return True

    if verbose:
        print("Armed: waiting for the next physical mouse click...", flush=True)
    with mouse.Listener(on_click=on_click) as ml:
        # Block until first click or listener stops
        while not done.is_set() and ml.running:
            time.sleep(0.01)


def main():
    args = parse_args()

    clicker = AutoClicker(interval=args.interval, count=args.count, button=args.button)

    start_armed_lock = threading.Lock()
    start_timer: threading.Timer | None = None

    def do_start_flow():
        nonlocal start_timer
        # Guard to avoid double-spawning from repeated hotkey presses
        with start_armed_lock:
            if clicker.is_running():
                if args.verbose:
                    print("Already running.", flush=True)
                return

            if args.start_after_click:
                wait_for_next_physical_click(verbose=args.verbose)
                clicker.start()
                if args.verbose:
                    print("Auto-clicker started.", flush=True)
                return

            if args.start_delay and args.start_delay > 0:
                if args.verbose:
                    print(f"Starting after {args.start_delay:.3f}s delay...", flush=True)

                def delayed_start():
                    clicker.start()
                    if args.verbose:
                        print("Auto-clicker started.", flush=True)

                # Cancel any existing timer before creating a new one
                if start_timer and start_timer.is_alive():
                    start_timer.cancel()
                start_timer = threading.Timer(args.start_delay, delayed_start)
                start_timer.daemon = True
                start_timer.start()
                return

            # Start immediately
            clicker.start()
            if args.verbose:
                print("Auto-clicker started.", flush=True)

    def do_stop_flow():
        nonlocal start_timer
        with start_armed_lock:
            if start_timer and start_timer.is_alive():
                start_timer.cancel()
            start_timer = None
        if clicker.is_running():
            clicker.stop()
            if args.verbose:
                print("Auto-clicker stopped.", flush=True)
        else:
            if args.verbose:
                print("Not running.", flush=True)

    # Prepare global hotkeys
    hotkeys = {
        args.hotkey_start: do_start_flow,
        args.hotkey_stop: do_stop_flow,
    }

    print("mac_autoclicker ready.")
    print(f"Start hotkey: {args.hotkey_start}")
    print(f"Stop hotkey:  {args.hotkey_stop}")
    if args.start_after_click:
        print("Mode: Start after first physical click (after pressing start hotkey)")
    elif args.start_delay and args.start_delay > 0:
        print(f"Mode: Delayed start of {args.start_delay:.3f}s (after pressing start hotkey)")
    else:
        print("Mode: Immediate start (when start hotkey pressed)")
    print(f"Interval: {args.interval}s | Count: {args.count if args.count>0 else 'infinite'} | Button: {args.button}")
    print("Grant Accessibility permissions to your terminal/app if prompted.")
    sys.stdout.flush()

    # macOS often requires Accessibility permissions for global hotkeys/mouse control
    # Run listeners in the foreground thread; this call blocks until program exit
    try:
        with keyboard.GlobalHotKeys(hotkeys) as h:
            h.join()
    except KeyboardInterrupt:
        pass
    finally:
        do_stop_flow()


if __name__ == "__main__":
    main()
