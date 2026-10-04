"""Append every prototype write and notification. Never write the auth key."""

from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LOG_DIR = ROOT / "docs" / "packets"


def open_log() -> Path:
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H-%M-%SZ")
    path = LOG_DIR / f"proto-{stamp}.log"
    path.write_text(f"# proto log {stamp}\n")
    return path


def log_packet(path: Path, direction: str, uuid: str, data: bytes) -> None:
    ts = datetime.now(timezone.utc).isoformat()
    hexed = data.hex()
    with path.open("a") as f:
        f.write(f"{ts} {direction} {uuid} {hexed}\n")
