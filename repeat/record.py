#!/usr/bin/env python3
"""Record the QEMU VGA console through QMP screendump.

Captures at a fixed target rate, writes JPEG frames plus index.csv, and sends
space keys during the initial boot so the Windows ISO's "press any key" prompt
does not fall through to an empty disk.
"""

import argparse
import csv
import datetime as dt
import os
import shutil
import signal
import subprocess
import sys
import time

from qmp import QMP


def log(message):
    stamp = dt.datetime.now().strftime("%H:%M:%S")
    print("[%s] %s" % (stamp, message), flush=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--qmp", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--interval", type=float, default=0.125)
    parser.add_argument("--quality", type=int, default=82)
    parser.add_argument("--tmp", default="/dev/shm/pcl-poc-frame.ppm")
    parser.add_argument("--boot-keys", action="store_true")
    parser.add_argument("--timeout", type=float, default=3600.0)
    args = parser.parse_args()

    os.makedirs(args.out, exist_ok=True)
    convert = shutil.which("convert")
    if not convert:
        log("ImageMagick convert not found")
        return 2

    qmp = None
    deadline = time.time() + 30.0
    while time.time() < deadline:
        try:
            qmp = QMP(args.qmp)
            log("QMP connected")
            break
        except Exception as exc:
            log("waiting for QMP: %s" % exc)
            time.sleep(0.2)
    if qmp is None:
        log("could not connect to QMP")
        return 2

    index_path = os.path.join(args.out, "index.csv")
    index = open(index_path, "w", newline="")
    writer = csv.writer(index)
    writer.writerow(["frame", "epoch_ms", "iso"])
    index.flush()

    stopped = {"flag": False}

    def stop(_signum, _frame):
        stopped["flag"] = True

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)

    start = time.time()
    next_at = start
    frame = 0
    key_at = [2.5, 3.5, 4.5, 5.5, 6.5] if args.boot_keys else []
    key_sent = set()
    failures = 0

    log("recording to %s (interval %.3fs)" % (args.out, args.interval))
    try:
        while not stopped["flag"] and time.time() - start < args.timeout:
            now = time.time()
            for when in key_at:
                if now - start >= when and when not in key_sent:
                    key_sent.add(when)
                    try:
                        qmp.sendkey("spc")
                        log("sent boot key at %.1fs" % (now - start))
                    except Exception as exc:
                        log("sendkey failed: %s" % exc)

            if now < next_at:
                time.sleep(next_at - now)

            target = os.path.join(args.out, "frame-%06d.jpg" % frame)
            try:
                response = qmp.screendump(args.tmp)
                if "error" in response:
                    raise RuntimeError(response["error"])
                subprocess.run(
                    [convert, args.tmp, "-quality", str(args.quality), target],
                    check=True,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    env=dict(os.environ, MAGICK_THREAD_LIMIT="1"),
                )
                stamp = time.time()
                writer.writerow(
                    [
                        frame,
                        int(stamp * 1000),
                        dt.datetime.fromtimestamp(stamp).isoformat(timespec="milliseconds"),
                    ]
                )
                index.flush()
                frame += 1
                failures = 0
            except EOFError:
                log("QMP closed; guest likely shut down")
                break
            except Exception as exc:
                failures += 1
                if failures <= 3 or failures % 50 == 0:
                    log("capture error (%d): %s" % (failures, exc))
                time.sleep(0.2)

            next_at += args.interval
            if next_at < time.time() - args.interval:
                next_at = time.time() + args.interval
    finally:
        index.close()
        qmp.close()
        log("stopped after %d frames, %.1fs" % (frame, time.time() - start))
    return 0


if __name__ == "__main__":
    sys.exit(main())
