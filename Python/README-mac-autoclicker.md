# macOS Auto-Clicker (Python)

A small, hotkey-enabled auto-clicker for macOS with:
- Delayed start or start after first physical click
- Adjustable interval between clicks
- Finite count or infinite clicking until stopped
- Global hotkeys to start/stop

Requires Accessibility permissions for your terminal or Python runtime.

## Install

```zsh
# Optional: create a virtual environment
python3 -m venv .venv
source .venv/bin/activate

# Install dependency
python3 -m pip install -r Python/requirements.txt
```

If prompted by macOS, grant Accessibility permissions to the app running the script (Terminal, iTerm, or VS Code).

- System Settings → Privacy & Security → Accessibility → enable your terminal/editor.

## Run

```zsh
python3 Python/mac_autoclicker.py --help
```

Common examples:

```zsh
# Start after a 2s delay when start hotkey is pressed
python3 Python/mac_autoclicker.py --start-delay 2 --interval 0.05 --count 100 --verbose

# Start only after the next physical click (after pressing start hotkey)
python3 Python/mac_autoclicker.py --start-after-click --interval 0.1 --count 0 --verbose

# Customize hotkeys
python3 Python/mac_autoclicker.py \
  --hotkey-start '<cmd>+<alt>+s' \
  --hotkey-stop '<cmd>+<alt>+x'
```

- Start hotkey: press to arm and start according to the selected mode.
- Stop hotkey: immediately stops any ongoing clicking.

## Notes
- Intervals under ~1–2 ms may be limited by system scheduling.
- If hotkeys or clicks do not work, re-check Accessibility permissions and re-run.
- This script uses `pynput` and simulates clicks at the current cursor location.