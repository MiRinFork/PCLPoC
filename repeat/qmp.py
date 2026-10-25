#!/usr/bin/env python3
"""Minimal QMP client for the PCL PoC VM."""

import json
import socket


class QMPError(RuntimeError):
    pass


class QMP:
    def __init__(self, path, timeout=10.0):
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.settimeout(timeout)
        self.sock.connect(path)
        self.f = self.sock.makefile("rwb", buffering=0)
        greeting = self._read()
        if "QMP" not in greeting:
            raise QMPError("not a QMP greeting: %r" % (greeting,))
        self._send({"execute": "qmp_capabilities"})
        self._read()

    def _read(self):
        line = self.f.readline()
        if not line:
            raise EOFError("QMP closed")
        return json.loads(line.decode("utf-8", "replace"))

    def _send(self, obj):
        self.f.write((json.dumps(obj) + "\n").encode("utf-8"))

    def cmd(self, name, args=None, timeout=15.0):
        self.sock.settimeout(timeout)
        request = {"execute": name}
        if args is not None:
            request["arguments"] = args
        self._send(request)
        while True:
            message = self._read()
            if "return" in message or "error" in message:
                return message

    def sendkey(self, key="spc"):
        return self.cmd(
            "human-monitor-command", {"command-line": "sendkey %s" % key}
        )

    def screendump(self, path):
        return self.cmd("screendump", {"filename": path})

    def status(self):
        return self.cmd("query-status", timeout=3.0)

    def quit(self):
        try:
            self.cmd("quit", timeout=3.0)
        except Exception:
            pass

    def close(self):
        try:
            self.f.close()
        except Exception:
            pass
        try:
            self.sock.close()
        except Exception:
            pass
