#!/usr/bin/python3 -I
"""Light daemon (fork only): keyboard (asusctl) + two Bluetooth LED strips.

Keeps the strips connected so changes are instant and software effects
(breathe / rainbow / strobe) can run. State is written to
~/.local/state/lights/state.json for the caelestia Lights tab.

  lightd.py                 run the daemon
  lightd.py send '<json>'   send a command, e.g.
      {"cmd": "colour", "targets": ["kb", "s1"], "hex": "05d9e8"}
      {"cmd": "brightness", "targets": [...], "value": 0-100}
      {"cmd": "power", "targets": [...], "on": true}
      {"cmd": "mode", "targets": [...], "mode": "static|breathe|rainbow|strobe"}
      {"cmd": "speed", "targets": [...], "speed": "slow|med|fast"}
      {"cmd": "timer", "minutes": 30}        (0 cancels; turns all lights off)
      {"cmd": "release"} / {"cmd": "reconnect"}
"""

import asyncio
import colorsys
import json
import math
import os
import subprocess
import sys
import time
from pathlib import Path

from bleak import BleakClient, BleakScanner

STATE_DIR = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state")) / "lights"
STATE_FILE = STATE_DIR / "state.json"
SOCKET = STATE_DIR / "lightd.sock"

STRIPS = {
    "s1": {"name": "LED strip 1", "mac": "41:42:7B:F8:94:5B", "proto": "leddmx",
           "char": "0000ffe1-0000-1000-8000-00805f9b34fb"},
    "s2": {"name": "LED strip 2", "mac": "E4:98:BB:D8:D2:91", "proto": "mrstar",
           "char": "0000fff3-0000-1000-8000-00805f9b34fb"},
}
SPEEDS = {"slow": 0.35, "med": 1.0, "fast": 2.5}
KB_LEVELS = ["off", "low", "med", "high"]


def rgb(hexs):
    hexs = hexs.lstrip("#")
    return tuple(int(hexs[i:i + 2], 16) for i in (0, 2, 4))


def hexstr(r, g, b):
    return "%02x%02x%02x" % (int(r), int(g), int(b))


class Light:
    def __init__(self, key, name):
        self.key, self.name = key, name
        self.on, self.hex, self.brightness = True, "05d9e8", 100
        self.mode, self.speed = "static", "med"
        self.connected = False

    def state(self):
        return {"name": self.name, "on": self.on, "hex": self.hex, "brightness": self.brightness,
                "mode": self.mode, "speed": self.speed, "connected": self.connected}


class Strip(Light):
    def __init__(self, key, cfg):
        super().__init__(key, cfg["name"])
        self.cfg = cfg
        self.client = None
        self.released = False
        self.lock = asyncio.Lock()
        self.last_frame = None

    def frames(self, r, g, b, on=True):
        p = self.cfg["proto"]
        if p == "leddmx":
            if not on:
                return [bytes([0x7B, 0x04, 0x04, 0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xBF])]
            return [bytes([0x7B, 0xFF, 0x07, int(r), int(g), int(b), 0x00, 0xFF, 0xBF])]
        # mrstar: hue/sat colour + separate brightness
        if not on:
            return [bytes([0xBC, 0x01, 0x01, 0x00, 0x55])]
        h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
        hue, sat, val = round(h * 360) % 360, round(s * 1000), max(10, round(v * 1024))
        return [bytes([0xBC, 0x04, 0x06, hue >> 8, hue & 255, sat >> 8, sat & 255, 0, 0, 0x55]),
                bytes([0xBC, 0x05, 0x06, val >> 8, val & 255, 0, 0, 0, 0, 0x55])]

    async def ensure(self):
        if self.released:
            return False
        if self.client and self.client.is_connected:
            return True
        try:
            dev = await BleakScanner.find_device_by_address(self.cfg["mac"], timeout=8)
            if not dev:
                self.connected = False
                return False
            self.client = BleakClient(dev, disconnected_callback=lambda _: self._lost())
            await self.client.connect(timeout=10)
            self.connected = True
            self.last_frame = None
            # power on first so later colour writes show
            await self._write_frames([self._power_on_frame()])
            return True
        except Exception as e:  # noqa: BLE001
            log(f"{self.key}: connect failed: {e}")
            self.connected = False
            self.client = None
            return False

    def _power_on_frame(self):
        if self.cfg["proto"] == "leddmx":
            return bytes([0x7B, 0x04, 0x04, 0x01, 0xFF, 0xFF, 0xFF, 0xFF, 0xBF])
        return bytes([0xBC, 0x01, 0x01, 0x01, 0x55])

    def _lost(self):
        self.connected = False

    async def _write_frames(self, frames):
        for f in frames:
            await self.client.write_gatt_char(self.cfg["char"], f, response=False)
            await asyncio.sleep(0.02)

    async def show(self, r, g, b, on=True):
        """Write a colour (already brightness-scaled) to the strip."""
        frames = self.frames(r, g, b, on)
        key = b"".join(frames)
        if key == self.last_frame:
            return
        async with self.lock:
            if not await self.ensure():
                return
            try:
                if on and self.last_frame is not None and self.last_frame.startswith(self.frames(0, 0, 0, False)[0]):
                    await self._write_frames([self._power_on_frame()])
                await self._write_frames(frames)
                self.last_frame = key
            except Exception as e:  # noqa: BLE001
                log(f"{self.key}: write failed: {e}")
                self.connected = False

    async def release(self):
        self.released = True
        if self.client:
            try:
                await self.client.disconnect()
            except Exception:  # noqa: BLE001
                pass
        self.client, self.connected = None, False


class Keyboard(Light):
    def __init__(self):
        super().__init__("kb", "Keyboard")
        self.connected = True
        self.applied = None

    def read(self):
        """Pick up changes made elsewhere (e.g. the utilities card)."""
        try:
            lvl = int(Path("/sys/class/leds/asus::kbd_backlight/brightness").read_text())
            out = subprocess.run(["busctl", "--system", "get-property", "xyz.ljones.Asusd", "/xyz/ljones/aura/tuf",
                                  "xyz.ljones.Aura", "LedModeData"], capture_output=True, text=True, timeout=3).stdout.split()
            mode = {0: "static", 1: "breathe", 2: "rainbow", 10: "strobe"}.get(int(out[1]), self.mode)
            hexs = hexstr(int(out[3]), int(out[4]), int(out[5]))
        except Exception:  # noqa: BLE001
            return
        want = self.applied
        if want and (lvl, mode, hexs) == want:
            return
        # external change
        self.on = lvl > 0
        if lvl > 0:
            self.brightness = round(lvl / 3 * 100)
        self.mode, self.hex = mode, hexs
        self.applied = (lvl, mode, hexs)

    def apply(self):
        lvl = 0 if not self.on else max(1, round(self.brightness / 100 * 3))
        subprocess.run(["asusctl", "leds", "set", KB_LEVELS[lvl]], capture_output=True, timeout=5)
        if lvl:
            speed = {"slow": "low", "med": "med", "fast": "high"}[self.speed]
            base = ["asusctl", "aura", "effect"]
            cmd = {
                "static": base + ["static", "-c", self.hex],
                "breathe": base + ["breathe", "--colour", self.hex, "--colour2", "000000", "--speed", speed],
                "rainbow": base + ["rainbow-cycle", "--speed", speed],
                "strobe": base + ["pulse", "-c", self.hex],
            }[self.mode]
            subprocess.run(cmd, capture_output=True, timeout=5)
        self.applied = (lvl, self.mode, self.hex)


class Daemon:
    def __init__(self):
        self.kb = Keyboard()
        self.strips = {k: Strip(k, c) for k, c in STRIPS.items()}
        self.lights = {"kb": self.kb, **self.strips}
        self.timer_end = 0
        self.dirty = True
        self.load()

    # ---- persistence -------------------------------------------------------
    def load(self):
        try:
            data = json.loads(STATE_FILE.read_text())
            for k, l in self.lights.items():
                s = data.get("lights", {}).get(k, {})
                for f in ("on", "hex", "brightness", "mode", "speed"):
                    if f in s:
                        setattr(l, f, s[f])
            self.timer_end = data.get("timerEnd", 0) / 1000
        except Exception:  # noqa: BLE001
            pass

    def save(self):
        data = {"lights": {k: l.state() for k, l in self.lights.items()},
                "timerEnd": int(self.timer_end * 1000), "updated": int(time.time() * 1000)}
        tmp = STATE_FILE.with_suffix(".tmp")
        tmp.write_text(json.dumps(data))
        tmp.replace(STATE_FILE)

    # ---- commands -----------------------------------------------------------
    def handle(self, msg):
        cmd = msg.get("cmd")
        targets = [self.lights[t] for t in msg.get("targets", []) if t in self.lights]
        kb_changed = False
        for l in targets:
            if cmd == "colour":
                l.hex, l.on = msg["hex"].lstrip("#").lower(), True
                if l.mode == "rainbow":
                    l.mode = "static"
            elif cmd == "brightness":
                l.brightness, l.on = max(1, min(100, int(msg["value"]))), True
            elif cmd == "power":
                l.on = bool(msg["on"])
            elif cmd == "mode":
                l.mode, l.on = msg["mode"], True
            elif cmd == "speed":
                l.speed = msg["speed"]
            kb_changed |= l is self.kb
        if cmd == "timer":
            m = float(msg.get("minutes", 0))
            self.timer_end = time.time() + m * 60 if m > 0 else 0
        elif cmd == "release":
            for s in self.strips.values():
                asyncio.ensure_future(s.release())
        elif cmd == "reconnect":
            for s in self.strips.values():
                s.released = False
                s.last_frame = None
        if kb_changed:
            asyncio.get_running_loop().run_in_executor(None, self.kb.apply)
        self.dirty = True

    async def serve(self):
        if SOCKET.exists():
            SOCKET.unlink()

        async def client(reader, writer):
            try:
                line = await reader.readline()
                self.handle(json.loads(line))
                writer.write(b"ok\n")
            except Exception as e:  # noqa: BLE001
                writer.write(f"error {e}\n".encode())
            await writer.drain()
            writer.close()

        server = await asyncio.start_unix_server(client, path=str(SOCKET))
        async with server:
            await server.serve_forever()

    # ---- loops --------------------------------------------------------------
    @staticmethod
    def frame_colour(light, t):
        """Colour the strip should show at time t (software effects)."""
        if not light.on:
            return None
        r, g, b = rgb(light.hex)
        k = light.brightness / 100
        sp = SPEEDS.get(light.speed, 1.0)
        if light.mode == "breathe":
            k *= 0.12 + 0.88 * (0.5 + 0.5 * math.sin(t * sp * 2.2))
        elif light.mode == "strobe":
            k *= 1 if (t * sp * 4) % 1 < 0.5 else 0.05
        elif light.mode == "rainbow":
            h = (t * sp * 0.08) % 1
            r, g, b = (c * 255 for c in colorsys.hsv_to_rgb(h, 1, 1))
        return round(r * k), round(g * k), round(b * k)

    async def strip_loop(self, strip):
        while True:
            t = time.time()
            c = self.frame_colour(strip, t)
            if c is None:
                await strip.show(0, 0, 0, on=False)
            else:
                await strip.show(*c)
            animated = strip.on and strip.mode != "static"
            await asyncio.sleep(0.08 if animated else 0.3)

    async def housekeeping(self):
        n = 0
        while True:
            if self.timer_end and time.time() >= self.timer_end:
                self.timer_end = 0
                for l in self.lights.values():
                    l.on = False
                await asyncio.get_running_loop().run_in_executor(None, self.kb.apply)
                self.dirty = True
            if n % 6 == 0:
                await asyncio.get_running_loop().run_in_executor(None, self.kb.read)
                self.dirty = True
            if self.dirty:
                self.save()
                self.dirty = False
            n += 1
            await asyncio.sleep(0.5)

    async def run(self):
        STATE_DIR.mkdir(parents=True, exist_ok=True)
        self.kb.read()
        self.save()
        await asyncio.gather(self.serve(), self.housekeeping(),
                             *(self.strip_loop(s) for s in self.strips.values()))


def log(msg):
    print(time.strftime("%H:%M:%S"), msg, file=sys.stderr, flush=True)


async def send(payload):
    reader, writer = await asyncio.open_unix_connection(str(SOCKET))
    writer.write(payload.encode().strip() + b"\n")
    await writer.drain()
    print((await reader.readline()).decode().strip())
    writer.close()


if __name__ == "__main__":
    if len(sys.argv) > 2 and sys.argv[1] == "send":
        asyncio.run(send(sys.argv[2]))
    else:
        asyncio.run(Daemon().run())
