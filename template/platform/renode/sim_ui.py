#!/usr/bin/env python3
"""Small GUI for `make sim-ui`: shows the LEDs and B1 of the simulated Nucleo.

Starts Renode with its monitor on a TCP port (-P), then talks to it like a person in the
Renode console would: every POLL_MS it asks `<led> State` (answer True/False), and the B1
button sends `Press` / `Release`. Polling means pulses shorter than POLL_MS can be missed;
for blinking and traffic lights that does not matter.

Renode's log (including "LED state changed to ...") stays in the terminal.
"""
import argparse
import queue
import signal
import re
import socket
import subprocess
import sys
import threading
import time
import tkinter as tk

POLL_MS = 50

# (Renode peripheral, label, colour when on) - must match nucleo_f401re.repl
LEDS = [
    ("sysbus.gpioPortA.UserLED", "LD2 (PA5)", "#7cb342"),
]
BUTTON = "sysbus.gpioPortC.UserButton"
OFF_COLOUR = "#3a3a3a"

PROMPT = re.compile(rb"\(\S+\) $")  # "(nucleo) " or "(monitor) " at the end of the buffer
SYNC = "SIMUI_SYNC"


class Monitor:
    """Line protocol over Renode's telnet monitor: send a command, read until the next prompt."""

    def __init__(self, port, alive, timeout_s=60):
        deadline = time.monotonic() + timeout_s
        while True:
            try:
                self.sock = socket.create_connection(("127.0.0.1", port), timeout=5)
                break
            except OSError:
                if not alive() or time.monotonic() > deadline:
                    raise
                time.sleep(0.2)
        # The 5 s were for connecting only. Startup (first run downloads an SVD) and answers
        # may take longer; Renode closing the socket still ends recv().
        self.sock.settimeout(None)
        self.startup = self._sync()

    def _sync(self):
        """Read past the banner and all startup output, however many prompts it contains.

        Renode answers commands in order, so once our echo comes back, everything before it
        belongs to the startup script. Returns those lines (they may contain errors).
        """
        self.sock.sendall(f'echo "{SYNC}"\n'.encode())  # unquoted, Renode reads a device name
        buf = b""
        while True:
            buf += self._read_until_prompt()
            lines = [l.strip() for l in buf.decode(errors="replace").splitlines()]
            if SYNC in lines:
                return lines[: lines.index(SYNC)]

    def _read_until_prompt(self):
        buf = b""
        while not PROMPT.search(buf):
            chunk = self.sock.recv(4096)
            if not chunk:
                raise ConnectionError("Renode hat die Verbindung geschlossen")
            buf += chunk
        return buf

    def command(self, cmd):
        self.sock.sendall(cmd.encode() + b"\n")
        reply = self._read_until_prompt()
        # reply = echo of cmd, result lines, prompt
        lines = [l.strip() for l in reply.decode(errors="replace").splitlines()]
        if not lines or not lines[0].endswith(cmd):
            raise ConnectionError(f"Antwort passt nicht zu '{cmd}': {lines[:2]}")
        return [l for l in lines[1:-1] if l]

    def close(self):
        try:
            self.sock.sendall(b"quit\n")
        except OSError:
            pass
        self.sock.close()


def port_in_use(port):
    with socket.socket() as s:
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)  # ignore TIME_WAIT, like Renode
        try:
            s.bind(("", port))  # Renode listens on 0.0.0.0
        except OSError:
            return True
    return False


def startup_errors(lines):
    """Renode reports a failed command as "There was an error executing command ..." plus
    one line with the reason."""
    for i, line in enumerate(lines):
        if line.startswith("There was an error"):
            return lines[i : i + 2]
    return []


def worker(mon, commands, states, stop):
    """Owns the socket: sends queued button commands, then polls all LEDs. False = connection lost."""
    while not stop.is_set():
        try:
            try:
                while True:
                    mon.command(commands.get_nowait())
            except queue.Empty:
                pass
            snapshot = [("True" in mon.command(f"{name} State")) for name, _, _ in LEDS]
        except OSError as e:  # ConnectionError is an OSError
            if stop.is_set():
                return True  # we closed the socket ourselves (shutdown)
            stop.set()
            states.put(f"Verbindung zu Renode verloren: {e}")
            return False
        states.put(snapshot)
        time.sleep(POLL_MS / 1000)
    return True


def build_ui(root, commands):
    root.title("Nucleo-F401RE (Renode)")
    root.configure(bg="#202020", padx=16, pady=16)
    canvas = tk.Canvas(root, width=260, height=60 * len(LEDS), bg="#202020", highlightthickness=0)
    canvas.pack()
    dots = []
    for i, (_, label, _) in enumerate(LEDS):
        y = 30 + 60 * i
        dots.append(canvas.create_oval(10, y - 22, 54, y + 22, fill=OFF_COLOUR, outline="#555"))
        canvas.create_text(72, y, text=label, anchor="w", fill="#ddd", font=("sans", 13))

    button = tk.Button(root, text="B1 (PC13) - halten = gedrückt", font=("sans", 12))
    button.pack(fill="x", pady=(12, 0))
    button.bind("<ButtonPress-1>", lambda e: commands.put(f"{BUTTON} Press"))
    button.bind("<ButtonRelease-1>", lambda e: commands.put(f"{BUTTON} Release"))
    status = tk.Label(root, text="verbinde mit Renode ...", bg="#202020", fg="#999")
    status.pack(pady=(8, 0))
    return canvas, dots, status


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--elf", required=True)
    ap.add_argument("--repl", required=True)
    ap.add_argument("--resc", required=True)
    ap.add_argument("--port", type=int, default=1234, help="TCP port for the Renode monitor")
    args = ap.parse_args()

    # Busy port: maybe another Renode listens there, and we would steer that one instead.
    if port_in_use(args.port):
        sys.exit(f"Port {args.port} ist belegt (läuft schon ein make sim-ui?). "
                 f"Anderer Port: make sim-ui SIM_PORT=...")

    root = tk.Tk()  # before Renode: without a display this fails and leaves nothing behind
    renode = subprocess.Popen([
        "renode", "--disable-gui", "--plain", "-P", str(args.port),
        "-e", f"$elf=@{args.elf}",
        "-e", f"$platform=@{args.repl}",
        "-e", f"include @{args.resc}",
    ])

    commands, states, stop = queue.Queue(), queue.Queue(), threading.Event()
    failed = threading.Event()  # decides the exit code, so make sees a broken simulation
    canvas, dots, status = build_ui(root, commands)

    def connect():
        try:
            mon = Monitor(args.port, alive=lambda: renode.poll() is None)
        except OSError as e:
            failed.set()
            stop.set()
            states.put(f"keine Verbindung zu Renode auf Port {args.port}: {e}")
            return
        root.mon = mon
        # An error aborts nucleo.resc before `start`, so the CPU never runs (e.g. GDB port
        # 3333 taken by a running make sim). Show the message instead of dark LEDs.
        errors = startup_errors(mon.startup)
        if errors:
            failed.set()
            stop.set()
            states.put("Startskript abgebrochen, Simulation läuft nicht:\n" + "\n".join(errors))
            return
        states.put("läuft - GDB: make sim-gdb")
        if not worker(mon, commands, states, stop):
            failed.set()

    root.mon = None
    root.renode_gone = False
    threading.Thread(target=connect, daemon=True).start()

    # Tk swallows exceptions raised in callbacks, so a KeyboardInterrupt from Ctrl-C does not
    # reliably end mainloop. Signals only set a flag; refresh() (every POLL_MS) acts on it.
    quit_requested = threading.Event()
    for sig in (signal.SIGINT, signal.SIGTERM):
        signal.signal(sig, lambda *_: quit_requested.set())

    def refresh():
        if quit_requested.is_set():
            shutdown()
            return
        try:
            while True:
                item = states.get_nowait()
                if isinstance(item, str):
                    # error paths set stop before they put their message
                    status.config(text=item, fg="#ef5350" if stop.is_set() else "#999")
                    continue
                for dot, on, (_, _, colour) in zip(dots, item, LEDS):
                    canvas.itemconfig(dot, fill=colour if on else OFF_COLOUR)
        except queue.Empty:
            pass
        if renode.poll() is not None and not root.renode_gone:
            root.renode_gone = True
            status.config(text=f"Renode beendet (Exit-Code {renode.returncode})", fg="#ef5350")
            stop.set()
        root.after(POLL_MS, refresh)

    def shutdown(*_):
        stop.set()
        if root.mon:
            root.mon.close()
        try:
            renode.wait(timeout=5)
        except subprocess.TimeoutExpired:
            renode.terminate()
        root.destroy()

    root.protocol("WM_DELETE_WINDOW", shutdown)
    root.bind("<Control-q>", shutdown)
    refresh()
    root.mainloop()
    if renode.poll() is None:
        renode.terminate()
        renode.wait()
    sys.exit(1 if failed.is_set() or renode.returncode else 0)


if __name__ == "__main__":
    main()
