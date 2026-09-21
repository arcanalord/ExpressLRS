#!/usr/bin/env python3
import contextlib
import http.server
import pathlib
import socket
import threading
import time
import sys

from playwright.sync_api import sync_playwright

root = pathlib.Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else pathlib.Path(".").resolve()

class QuietHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *_args):
        pass

def free_port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]

port = free_port()
handler = lambda *a, **kw: QuietHandler(*a, directory=str(root), **kw)
server = http.server.ThreadingHTTPServer(("127.0.0.1", port), handler)
thread = threading.Thread(target=server.serve_forever, daemon=True)
thread.start()

errors = []
try:
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        context = browser.new_context(
            viewport={"width": 412, "height": 915},
            service_workers="block",
        )
        page = context.new_page()
        page.add_init_script("window.__meshDisableAutoConnect=true;")
        page.route("https://tile.openstreetmap.org/**", lambda route: route.abort())
        page.on("pageerror", lambda exc: errors.append(f"pageerror: {exc}"))
        page.on("console", lambda msg: errors.append(f"console error: {msg.text}") if msg.type == "error" else None)

        page.goto(f"http://127.0.0.1:{port}/index.html", wait_until="domcontentloaded")
        page.wait_for_timeout(500)

        if page.evaluate("typeof window.__meshDebug") != "object":
            raise AssertionError("window.__meshDebug missing: startup did not finish")

        active = page.locator(".view.is-active").get_attribute("data-screen")
        if active != "chats":
            raise AssertionError(f"expected initial chats view, got {active!r}")

        for view in ("map", "network", "settings", "chats"):
            page.locator(f".mobile-bottom-nav [data-view='{view}']").click()
            page.wait_for_timeout(80)
            active = page.locator(".view.is-active").get_attribute("data-screen")
            if active != view:
                raise AssertionError(f"navigation failed: {view!r} -> {active!r}")

        page.locator("#helpTriggerMobile").click()
        page.wait_for_timeout(50)
        if page.locator("#quickHelpModal").get_attribute("aria-hidden") != "false":
            raise AssertionError("Help trigger did not open Quick Help")
        page.locator("#closeQuickHelp").click()

        page.locator("#newContactButton").click()
        page.wait_for_timeout(50)
        if page.locator("#addMenuModal").get_attribute("aria-hidden") != "false":
            raise AssertionError("Add menu did not open")
        page.locator("#closeAddMenu").click()

        if errors:
            raise AssertionError("; ".join(errors))

        print("UI_STARTUP_SMOKE_PASS")
        browser.close()
finally:
    server.shutdown()
    server.server_close()
