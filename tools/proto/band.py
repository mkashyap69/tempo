"""Stage B: auth, 60s live HR, 24h activity dump.

Every opcode is TODO(verify) until this log or docs/packets/reference-mifitness.pcap
shows the same bytes. Confirmed on firmware V1.0.6.20 (2026-10-03 capture):
classic request 02 00 -> 10 02 01 + 16B, short-new 82 00 02 -> 10 82 01 + 16B,
then both encrypted replies came back status 07 (key rejected).

Force-stop Mi Fitness before running. One connection at a time.
"""

from __future__ import annotations

import argparse
import asyncio
import os
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

from bleak import BleakClient, BleakScanner
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from dotenv import load_dotenv

from log_packet import LOG_DIR, log_packet, open_log

HUAMI = "-0000-3512-2118-0009af100700"
AUTH = f"00000009{HUAMI}"
FETCH = f"00000004{HUAMI}"
ACTIVITY = f"00000005{HUAMI}"
HR_MEAS = "00002a37-0000-1000-8000-00805f9b34fb"
HR_CTRL = "00002a39-0000-1000-8000-00805f9b34fb"
FW_REV = "00002a26-0000-1000-8000-00805f9b34fb"
SW_REV = "00002a28-0000-1000-8000-00805f9b34fb"

# TODO(verify): capture wins over these prefixes.
VARIANTS = [
    ("classic", b"\x02\x00", b"\x10\x02\x01", b"\x03\x00", b"\x10\x03\x01"),
    ("new", b"\x82\x00\x02\x01\x00", b"\x10\x82\x01", b"\x83\x00", b"\x10\x83\x01"),
    # 3-byte request already elicited 10 82 01 on V1.0.6.20.
    ("new-short", b"\x82\x00\x02", b"\x10\x82\x01", b"\x83\x00", b"\x10\x83\x01"),
]

# TODO(verify) type bytes other than activity.
TYPES = {"activity": 0x01, "stress": 0x14, "spo2": 0x25}


def load_key() -> bytes:
    root = Path(__file__).resolve().parents[2]
    load_dotenv(root / ".env")
    raw = os.environ.get("MIBAND_AUTH_KEY") or os.environ.get("BAND_AUTH_KEY") or ""
    raw = raw.strip().removeprefix("0x")
    if len(raw) != 32 or any(c not in "0123456789abcdefABCDEF" for c in raw):
        sys.exit("Set BAND_AUTH_KEY in .env to 32 hex chars. The key is not logged.")
    return bytes.fromhex(raw)


def aes_ecb(key: bytes, block: bytes) -> bytes:
    enc = Cipher(algorithms.AES(key), modes.ECB()).encryptor()
    return enc.update(block) + enc.finalize()


class Band:
    def __init__(self, client: BleakClient, log: Path):
        self.client = client
        self.log = log
        self.lock = asyncio.Lock()
        self._q: dict[str, asyncio.Queue[bytes]] = {}

    def _on(self, uuid: str):
        def cb(_sender, data: bytearray) -> None:
            blob = bytes(data)
            log_packet(self.log, "rx", uuid, blob)
            q = self._q.get(uuid)
            if q is not None:
                q.put_nowait(blob)

        return cb

    async def subscribe(self, uuid: str) -> asyncio.Queue[bytes]:
        q: asyncio.Queue[bytes] = asyncio.Queue()
        self._q[uuid] = q
        await self.client.start_notify(uuid, self._on(uuid))
        return q

    def _char(self, uuid: str):
        for service in self.client.services:
            for char in service.characteristics:
                if str(char.uuid) == uuid:
                    return char
        return None

    async def write(self, uuid: str, data: bytes) -> None:
        char = self._char(uuid)
        response = char is not None and "write" in char.properties
        async with self.lock:
            log_packet(self.log, "tx", uuid, data)
            await self.client.write_gatt_char(uuid, data, response=response)

    async def read(self, uuid: str) -> bytes:
        async with self.lock:
            data = bytes(await self.client.read_gatt_char(uuid))
        log_packet(self.log, "rx", uuid, data)
        return data

    def dump_gatt(self) -> None:
        lines = []
        for service in self.client.services:
            lines.append(f"service {service.uuid}")
            for char in service.characteristics:
                props = ",".join(char.properties)
                lines.append(f"  char {char.uuid} [{props}]")
        text = "\n".join(lines) + "\n"
        (LOG_DIR / "gatt-dump.txt").write_text(text)
        print(text, end="")
        missing = [u for u in (AUTH, FETCH, ACTIVITY) if self._char(u) is None]
        if missing:
            print("missing:", ", ".join(missing))


async def find_address(explicit: str | None) -> str:
    if explicit:
        return explicit
    print("scanning 12s for Mi Smart Band 6")
    devices = await BleakScanner.discover(timeout=12)
    hits = []
    for d in devices:
        name = d.name or ""
        print(f"  {d.address}  {name}")
        if "band" in name.lower():
            hits.append(d)
    if not hits:
        sys.exit("Band not seen. Force-stop Mi Fitness, toggle the phone's Bluetooth, retry.")
    chosen = hits[0]
    print(f"using {chosen.address} ({chosen.name})")
    print(f"Set MIBAND_ADDRESS={chosen.address} in .env to skip the scan.")
    return chosen.address


async def authenticate(band: Band, key: bytes) -> str | None:
    q = await band.subscribe(AUTH)
    rejects = 0
    for name, req, got, send, ok in VARIANTS:
        print(f"auth: trying {name} req={req.hex()}")
        while not q.empty():
            q.get_nowait()
        await band.write(AUTH, req)
        try:
            challenge = await asyncio.wait_for(q.get(), 5)
        except TimeoutError:
            print(f"auth: {name} no challenge")
            continue
        print(f"auth: {name} rx={challenge.hex()}")
        if not challenge.startswith(got):
            print(f"auth: {name} prefix mismatch, capture wins — edit VARIANTS")
            continue
        block = challenge[3:19]
        if len(block) != 16:
            print(f"auth: {name} challenge is {len(block)} bytes, need 16")
            continue
        await band.write(AUTH, send + aes_ecb(key, block))
        try:
            result = await asyncio.wait_for(q.get(), 5)
        except TimeoutError:
            print(f"auth: {name} no final status")
            continue
        print(f"auth: {name} status={result.hex()}")
        if result.startswith(ok):
            print(f"auth: OK via {name}")
            await band.client.stop_notify(AUTH)
            return name
        rejects += 1
        if rejects >= 2:
            print("auth: two variants returned a challenge then a non-ok status.")
            print("That is a wrong key for this pairing. Re-extract it; check the MAC.")
            return None
    print("auth: no variant succeeded")
    return None


def parse_hr(data: bytes) -> int | None:
    if not data:
        return None
    if data[0] & 0x01:
        if len(data) < 3:
            return None
        return data[1] | (data[2] << 8)
    if len(data) < 2:
        return None
    return data[1]


async def live_hr(band: Band, seconds: int) -> None:
    q = await band.subscribe(HR_MEAS)
    # TODO(verify): 15 01 01 and keep-alive 16 against the reference capture.
    await band.write(HR_CTRL, b"\x15\x01\x01")

    async def keepalive() -> None:
        while True:
            await asyncio.sleep(12)
            await band.write(HR_CTRL, b"\x16")

    task = asyncio.create_task(keepalive())
    deadline = asyncio.get_running_loop().time() + seconds
    last = None
    try:
        while asyncio.get_running_loop().time() < deadline:
            try:
                data = await asyncio.wait_for(q.get(), 5)
            except TimeoutError:
                print("hr: no measurement for 5s")
                continue
            bpm = parse_hr(data)
            if bpm != last:
                print(f"hr: {bpm} bpm  raw={data.hex()}")
                last = bpm
    finally:
        task.cancel()
        await band.write(HR_CTRL, b"\x15\x01\x00")


def encode_since(when: datetime) -> bytes:
    local = when.astimezone()
    off = local.utcoffset() or timedelta(0)
    tz = int(off.total_seconds() // 60) // 15  # TODO(verify) quarter-hours
    year = local.year
    return bytes(
        [
            year & 0xFF,
            (year >> 8) & 0xFF,
            local.month,
            local.day,
            local.hour,
            local.minute,
            tz & 0xFF,
        ]
    )


async def fetch_activity(band: Band, since: datetime, stamp: str) -> None:
    ctrl = await band.subscribe(FETCH)
    data_q = await band.subscribe(ACTIVITY)
    cmd = bytes([0x01, TYPES["activity"]]) + encode_since(since)
    print(f"fetch: tx {cmd.hex()} since {since.isoformat(timespec='minutes')}")
    await band.write(FETCH, cmd)
    try:
        header = await asyncio.wait_for(ctrl.get(), 8)
    except TimeoutError:
        print("fetch: no header on 0004")
        return
    print(f"fetch: header {header.hex()}")
    if len(header) >= 7 and header[0] == 0x10 and header[1] == 0x01:
        count = int.from_bytes(header[3:7], "little")
        print(f"fetch: count={count}")
        if count == 0:
            print("fetch: 0 records. Since-time or timezone byte is wrong.")
            return
    await band.write(FETCH, b"\x02")
    packets: list[bytes] = []
    while True:
        got_ctrl = asyncio.create_task(ctrl.get())
        got_data = asyncio.create_task(data_q.get())
        done, pending = await asyncio.wait(
            {got_ctrl, got_data},
            timeout=8,
            return_when=asyncio.FIRST_COMPLETED,
        )
        for task in pending:
            task.cancel()
        if pending:
            await asyncio.gather(*pending, return_exceptions=True)
        if not done:
            print("fetch: idle 8s, stopping")
            break
        if got_ctrl in done:
            msg = got_ctrl.result()
            print(f"fetch: ctrl {msg.hex()}")
            if len(msg) >= 3 and msg[0] == 0x10 and msg[1] == 0x02:
                break
        if got_data in done:
            packets.append(got_data.result())
    raw_path = LOG_DIR / f"proto-{stamp}-activity.hex"
    raw_path.write_text("".join(p.hex() + "\n" for p in packets))
    print(f"fetch: {len(packets)} data packets -> {raw_path.name}")
    parse_activity(packets, header, stamp)


def record_size(packets: list[bytes]) -> int | None:
    """Smallest candidate that divides (packet_len - 1) on every packet."""
    bodies = [len(p) - 1 for p in packets if len(p) > 1]
    if not bodies:
        return None
    hits = [n for n in (4, 5, 6, 8) if all(n and b % n == 0 for b in bodies)]
    if not hits:
        return None
    if len(hits) > 1:
        print(f"parse: sizes that divide every packet: {hits}; using {hits[0]}")
    return hits[0]


def parse_activity(packets: list[bytes], header: bytes, stamp: str) -> None:
    if not packets:
        print("parse: no data packets")
        return
    size = record_size(packets)
    if size is None:
        print("parse: no record size divides every packet. Left raw.")
        for p in packets[:5]:
            print(f"  len={len(p)} {p.hex()}")
        return
    print(f"parse: record size {size} (TODO(verify) fields)")
    start = None
    if len(header) >= 14 and header[0] == 0x10:
        # year u16 LE, month, day, hour, minute at offset 7. TODO(verify)
        year = header[7] | (header[8] << 8)
        try:
            start = datetime(year, header[9], header[10], header[11], header[12])
        except ValueError:
            start = None
    rows = []
    minute = 0
    for packet in packets:
        body = packet[1:]
        for off in range(0, len(body) - size + 1, size):
            rec = body[off : off + size]
            ts = (
                (start + timedelta(minutes=minute)).isoformat(timespec="minutes")
                if start
                else str(minute)
            )
            hr = rec[3] if size >= 4 else None
            if hr in (0, 255):
                hr = None
            kind, intensity, steps = rec[0], rec[1], rec[2]
            rows.append((ts, kind, intensity, steps, hr if hr is not None else ""))
            minute += 1
    out = LOG_DIR / f"proto-{stamp}-activity.csv"
    with out.open("w") as f:
        f.write("ts,kind,intensity,steps,hr\n")
        for row in rows:
            f.write(",".join(str(x) for x in row) + "\n")
    print(f"parse: {len(rows)} minutes -> {out.name}")
    if rows:
        print("last 5 minutes:")
        for row in rows[-5:]:
            print(" ", row)


async def run(args: argparse.Namespace) -> None:
    key = load_key()
    address = await find_address(args.address or os.environ.get("MIBAND_ADDRESS") or os.environ.get("MIBAND_MAC"))
    log = open_log()
    stamp = log.stem.removeprefix("proto-")
    print(f"log {log.relative_to(Path(__file__).resolve().parents[2])}")
    async with BleakClient(address, timeout=20) as client:
        band = Band(client, log)
        band.dump_gatt()
        for uuid, label in ((FW_REV, "firmware"), (SW_REV, "software")):
            if band._char(uuid) is None:
                print(f"{label}: characteristic absent")
                continue
            raw = await band.read(uuid)
            print(f"{label}: {raw.decode('utf-8', 'replace')} ({raw.hex()})")
        if args.gatt_only:
            return
        variant = await authenticate(band, key)
        if variant is None or args.auth_only:
            if variant is None:
                sys.exit(1)
            return
        await live_hr(band, args.hr_seconds)
        since = datetime.now(timezone.utc) - timedelta(hours=args.since_hours)
        await fetch_activity(band, since, stamp)


def self_test() -> None:
    key = bytes.fromhex("000102030405060708090a0b0c0d0e0f")
    plain = bytes.fromhex("00112233445566778899aabbccddeeff")
    out = aes_ecb(key, plain).hex()
    if out != "69c4e0d86a7b0430d8cdb78070b4c55a":
        sys.exit(f"aes self-test failed: {out}")
    enc = encode_since(datetime(2026, 10, 4, 12, 30, tzinfo=timezone.utc))
    if enc[0] != (2026 & 0xFF) or enc[1] != (2026 >> 8) or enc[2:6] != bytes([10, 4, 12, 30]):
        sys.exit(f"timestamp self-test failed: {enc.hex()}")
    if record_size([bytes([0, 1, 2, 3, 70]), bytes([1, 1, 2, 3, 71])]) != 4:
        sys.exit("record-size self-test failed")
    if parse_hr(bytes([0x00, 72])) != 72:
        sys.exit("hr self-test failed")
    print("self-test ok")


def main() -> None:
    p = argparse.ArgumentParser(description="Mi Band 6 Stage B prototype")
    p.add_argument("--address", help="MAC, or CoreBluetooth UUID on macOS")
    p.add_argument("--gatt-only", action="store_true")
    p.add_argument("--auth-only", action="store_true")
    p.add_argument("--self-test", action="store_true")
    p.add_argument("--hr-seconds", type=int, default=60)
    p.add_argument("--since-hours", type=int, default=24)
    args = p.parse_args()
    if args.self_test:
        self_test()
        return
    asyncio.run(run(args))


if __name__ == "__main__":
    main()
