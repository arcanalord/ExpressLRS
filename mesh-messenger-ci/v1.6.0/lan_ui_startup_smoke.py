#!/usr/bin/env python3
import http.server
import pathlib
import socket
import threading
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

port=free_port()
handler=lambda *a, **kw: QuietHandler(*a, directory=str(root), **kw)
server=http.server.ThreadingHTTPServer(("127.0.0.1",port),handler)
threading.Thread(target=server.serve_forever,daemon=True).start()
errors=[]

try:
    with sync_playwright() as p:
        import shutil
        executable=(shutil.which("google-chrome") or shutil.which("google-chrome-stable") or shutil.which("chromium") or shutil.which("chromium-browser"))
        args={"headless":True}
        if executable: args["executable_path"]=executable
        browser=p.chromium.launch(**args)
        context=browser.new_context(viewport={"width":412,"height":915},service_workers="block")
        page=context.new_page()
        page.add_init_script("window.__meshDisableAutoConnect=true; localStorage.clear();")
        page.route("https://tile.openstreetmap.org/**",lambda route:route.abort())
        page.on("pageerror",lambda exc:errors.append(f"pageerror: {exc}"))
        page.on("console",lambda msg:errors.append(f"console error: {msg.text}") if msg.type=="error" and "Failed to load resource" not in msg.text else None)

        page.goto(f"http://127.0.0.1:{port}/index.html",wait_until="domcontentloaded")
        page.wait_for_timeout(400)

        if page.evaluate("typeof window.__meshDebug")!="object":
            raise AssertionError("window.__meshDebug missing: "+("; ".join(errors) or "startup incomplete"))

        if page.locator(".view.is-active").get_attribute("data-screen")!="chats":
            raise AssertionError("initial view is not chats")

        if page.locator("#nodeCount").is_visible():
            raise AssertionError("legacy node count is visible")
        if page.locator("#systemBanner").is_visible():
            raise AssertionError("legacy PhoneAPI banner is visible")
        body=page.locator("body").inner_text()
        for forbidden in ("Основной канал","QR-канал","7 узлов","ERROR · синхронизация не завершена"):
            if forbidden in body:
                raise AssertionError(f"legacy Wi-Fi-incompatible UI visible: {forbidden}")

        if "Пока нет контактов" not in page.locator("#conversationList").inner_text():
            raise AssertionError("empty contact state missing")

        page.locator("#newContactButton").click()
        page.wait_for_timeout(50)
        if page.locator("#fastPairModal").get_attribute("aria-hidden")!="false":
            raise AssertionError("+ did not open personal LAN contact pairing")
        if page.locator("#addMenuModal").get_attribute("aria-hidden")=="false":
            raise AssertionError("legacy quick actions opened instead of pairing")
        if page.locator("#saveFastPeer").is_enabled():
            raise AssertionError("contact save must stay disabled before contact identity is known")

        page.evaluate("""() => {
          const t=window.__meshDebug.lanTransport;
          t.remotePeerId='peer-offline-test';
          t.remoteName='Алексей';
          t.onState({state:'pairing',remotePeerId:t.remotePeerId,remoteName:t.remoteName});
        }""")
        page.wait_for_timeout(50)
        if not page.locator("#saveFastPeer").is_enabled():
            raise AssertionError("offline contact save must enable after identity is known, even without LAN READY")
        page.locator("#saveFastPeer").click()
        page.wait_for_timeout(80)
        if page.locator("#fastPairModal").get_attribute("aria-hidden")!="true":
            raise AssertionError("offline contact save did not close pairing modal")
        if "Алексей" not in page.locator("#conversationList").inner_text():
            raise AssertionError("offline-saved contact did not appear in Chats")
        modal=page.locator("#fastPairModal").inner_text()
        if "личный контакт" not in modal.lower() or "не группа" not in modal.lower():
            raise AssertionError("pairing modal does not explain personal chat semantics")


        for view in ("map","network","settings","chats"):
            page.locator(f".mobile-bottom-nav [data-view='{view}']").click()
            page.wait_for_timeout(60)
            if page.locator(".view.is-active").get_attribute("data-screen")!=view:
                raise AssertionError(f"navigation failed: {view}")

        page.locator(".mobile-bottom-nav [data-view='map']").click()
        before=page.evaluate("window.__meshDebug.getMapViewport().zoom")
        page.locator("#mapZoomInButton").click()
        page.wait_for_timeout(60)
        after=page.evaluate("window.__meshDebug.getMapViewport().zoom")
        if not after>before:
            raise AssertionError("map zoom regression")

        page.locator(".mobile-bottom-nav [data-view='chats']").click()
        page.locator("#helpTriggerMobile").click()
        page.wait_for_timeout(40)
        if page.locator("#quickHelpModal").get_attribute("aria-hidden")!="false":
            raise AssertionError("Help did not open")
        page.locator("#closeQuickHelp").click()

        if errors:
            raise AssertionError("; ".join(errors))

        print("LAN_UI_STARTUP_SMOKE_PASS")
        browser.close()
finally:
    server.shutdown()
    server.server_close()
