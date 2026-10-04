"""Probe the V1.0.6.x chunked auth on characteristics 0016/0017.

Force-stop Mi Fitness first. The auth key is read from .env and never printed.
TODO(verify): endianness of the secp192r1 points. Little-endian is tried first.
"""

from __future__ import annotations

import asyncio
import os
import sys
from pathlib import Path
from sys import platform

from bleak import BleakClient, BleakScanner
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from dotenv import load_dotenv

HUAMI = "-0000-3512-2118-0009af100700"
WRITE = f"00000016{HUAMI}"
READ = f"00000017{HUAMI}"


def load_key() -> bytes:
    load_dotenv(Path(__file__).resolve().parents[2] / ".env")
    raw = (os.environ.get("BAND_AUTH_KEY") or "").strip().removeprefix("0x")
    if len(raw) != 32:
        sys.exit("BAND_AUTH_KEY missing")
    return bytes.fromhex(raw)


def chunks(handle: int, data: bytes, mtu: int = 23) -> list[bytes]:
    out = []
    offset = 0
    count = 0
    while offset < len(data):
        first = count == 0
        header = 11 if first else 5
        room = mtu - 3 - header
        n = min(len(data) - offset, room)
        last = offset + n == len(data)
        flags = (0x01 if first else 0) | (0x06 if last else 0)
        buf = bytearray(header + n)
        buf[0] = 0x03
        buf[1] = flags
        buf[3] = handle
        buf[4] = count
        if first:
            length = len(data)
            buf[5:9] = length.to_bytes(4, "little")
            buf[9] = 0x82
        buf[header:] = data[offset : offset + n]
        out.append(bytes(buf))
        offset += n
        count += 1
    return out


def point_bytes(numbers: ec.EllipticCurvePublicNumbers, endian: str) -> bytes:
    return numbers.x.to_bytes(24, endian) + numbers.y.to_bytes(24, endian)


def second_command(
    private: ec.EllipticCurvePrivateKey,
    auth: bytes,
    random16: bytes,
    remote_pub: bytes,
    endian: str,
) -> bytes:
    x = int.from_bytes(remote_pub[:24], endian)
    y = int.from_bytes(remote_pub[24:48], endian)
    peer = ec.EllipticCurvePublicNumbers(x, y, ec.SECP192R1()).public_key()
    shared = private.exchange(ec.ECDH(), peer)
    # cryptography returns the X coordinate big-endian.
    xle = shared[::-1] if endian == "little" else shared
    session = bytes(xle[i + 8] ^ auth[i] for i in range(16))

    def aes(key: bytes) -> bytes:
        enc = Cipher(algorithms.AES(key), modes.CBC(bytes(16))).encryptor()
        return enc.update(random16) + enc.finalize()

    return bytes([0x05]) + aes(auth) + aes(session)


class Reader:
    def __init__(self) -> None:
        self.buf = bytearray()
        self.expected: int | None = None
        self.events: asyncio.Queue[str] = asyncio.Queue()
        self._announced = False

    def add(self, data: bytes) -> None:
        print("rx", data.hex())
        if len(data) < 5 or data[0] != 0x03:
            return
        seq = data[4]
        marked = (
            len(data) >= 14
            and data[9] == 0x82
            and data[10] == 0x00
            and data[11] == 0x10
        )
        if seq == 0 and marked and data[12] == 0x04 and data[13] == 0x01:
            length = int.from_bytes(data[5:9], "little")
            self.expected = length - 3
            self.buf = bytearray(data[14:])
            self._announced = False
        elif seq == 0 and marked and data[12] == 0x05:
            self.events.put_nowait("ok" if data[13] == 0x01 else "fail")
            return
        elif seq > 0:
            self.buf += data[5:]
        if (
            self.expected is not None
            and len(self.buf) >= self.expected
            and not self._announced
        ):
            self._announced = True
            self.events.put_nowait("challenge")


async def once(address: str, auth: bytes, endian: str) -> bool:
    print(f"auth endian={endian}")
    private = ec.generate_private_key(ec.SECP192R1())
    pub = point_bytes(private.public_key().public_numbers(), endian)
    hello = bytes([0x04, 0x02, 0x00, 0x02]) + pub
    reader = Reader()
    async with BleakClient(address, timeout=20) as client:
        await client.start_notify(READ, lambda _s, d: reader.add(bytes(d)))
        for packet in chunks(0, hello):
            print("tx", packet.hex())
            await client.write_gatt_char(WRITE, packet, response=False)
        step = await asyncio.wait_for(reader.events.get(), 12)
        print("step", step, "body", len(reader.buf))
        if step != "challenge" or len(reader.buf) < 64:
            return False
        reply = second_command(private, auth, bytes(reader.buf[:16]), bytes(reader.buf[16:64]), endian)
        for packet in chunks(1, reply):
            print("tx", packet.hex())
            await client.write_gatt_char(WRITE, packet, response=False)
        result = await asyncio.wait_for(reader.events.get(), 12)
        print("result", result)
        return result == "ok"


async def main() -> None:
    auth = load_key()
    address = os.environ.get("MIBAND_ADDRESS")
    # macOS hides MACs. A 17-char Android address cannot be used as a CoreBluetooth id.
    if platform == "darwin" or not address or len(address) <= 17:
        print("scanning")
        found = await BleakScanner.discover(timeout=12)
        hits = [d for d in found if d.name and "band" in d.name.lower()]
        for d in found:
            print(f"  {d.address} {d.name}")
        if not hits:
            sys.exit("band not advertising. Turn the phone's Bluetooth off and retry.")
        address = hits[0].address
        print("using", address, hits[0].name)
    for endian in ("little", "big"):
        try:
            if await once(address, auth, endian):
                print("AUTH OK", endian)
                return
        except Exception as e:
            print(endian, "failed:", type(e).__name__, e)
    sys.exit(1)


if __name__ == "__main__":
    asyncio.run(main())
