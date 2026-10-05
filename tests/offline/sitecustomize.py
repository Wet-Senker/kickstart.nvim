"""Loaded only by Python children of run_headless.py; never in production."""

import os
import sys


def offline_network(event, args):
    if event != "socket.connect":
        return
    address = args[1]
    # Unix sockets and loopback remain available for local editor/browser tests.
    if not isinstance(address, tuple) or address[0] in ("127.0.0.1", "::1"):
        return
    marker = os.environ.get("TEXTTOOLS_TEST_NETWORK_VIOLATIONS")
    if marker:
        with open(marker, "a") as log:
            log.write("Blocked external socket.connect\n")
    raise RuntimeError("Live network forbidden in headless tests; mock the adapter.")


if os.environ.get("TEXTTOOLS_TEST_NETWORK_VIOLATIONS"):
    sys.addaudithook(offline_network)
