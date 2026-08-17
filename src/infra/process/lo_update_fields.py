import subprocess
import sys
import time
from pathlib import Path

import uno
from com.sun.star.beans import PropertyValue


def prop(name, value):
    item = PropertyValue()
    item.Name = name
    item.Value = value
    return item


def file_url(path):
    return Path(path).resolve().as_uri()


def connect(port):
    local_ctx = uno.getComponentContext()
    resolver = local_ctx.ServiceManager.createInstanceWithContext(
        "com.sun.star.bridge.UnoUrlResolver", local_ctx
    )
    url = f"uno:socket,host=127.0.0.1,port={port};urp;StarOffice.ComponentContext"
    deadline = time.time() + 30
    last_error = None
    while time.time() < deadline:
        try:
            return resolver.resolve(url)
        except Exception as exc:
            last_error = exc
            time.sleep(0.5)
    raise RuntimeError(f"could not connect to LibreOffice UNO: {last_error}")


def update_document(doc, desktop, ctx):
    try:
        doc.updateLinks()
    except Exception:
        pass

    for method_name in ("calculateAll", "updateAll"):
        method = getattr(doc, method_name, None)
        if method:
            try:
                method()
            except Exception:
                pass

    try:
        fields = doc.getTextFields().createEnumeration()
        while fields.hasMoreElements():
            try:
                fields.nextElement().update()
            except Exception:
                pass
    except Exception:
        pass

    try:
        indexes = doc.getDocumentIndexes()
        for idx in range(indexes.getCount()):
            indexes.getByIndex(idx).update()
    except Exception:
        pass

    try:
        frame = doc.getCurrentController().getFrame()
        dispatcher = ctx.ServiceManager.createInstanceWithContext(
            "com.sun.star.frame.DispatchHelper", ctx
        )
        for command in (".uno:SelectAll", ".uno:UpdateFields", ".uno:UpdateAllIndexes", ".uno:UpdateAll"):
            try:
                dispatcher.executeDispatch(frame, command, "", 0, ())
            except Exception:
                pass
    except Exception:
        pass


def main():
    if len(sys.argv) != 7:
        print("usage: lo_update_fields.py INPUT.docx OUTPUT.docx|- OUTPUT.pdf|- PROFILE_DIR PORT SOFFICE", file=sys.stderr)
        return 2

    source, target_docx, target_pdf, profile_dir, port, soffice = sys.argv[1:]
    profile = Path(profile_dir)
    profile.mkdir(parents=True, exist_ok=True)

    proc = subprocess.Popen(
        [
            soffice,
            "--headless",
            "--nologo",
            "--nodefault",
            "--nofirststartwizard",
            "--nolockcheck",
            f"-env:UserInstallation={profile.resolve().as_uri()}",
            f"--accept=socket,host=127.0.0.1,port={port};urp;StarOffice.ComponentContext",
        ],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )

    doc = None
    desktop = None
    try:
        ctx = connect(port)
        desktop = ctx.ServiceManager.createInstanceWithContext("com.sun.star.frame.Desktop", ctx)
        doc = desktop.loadComponentFromURL(
            file_url(source),
            "_blank",
            0,
            (
                prop("Hidden", True),
                prop("ReadOnly", False),
                prop("UpdateDocMode", 3),
            ),
        )
        if doc is None:
            raise RuntimeError("LibreOffice could not open source document")

        update_document(doc, desktop, ctx)
        if target_docx != "-":
            doc.storeAsURL(
                file_url(target_docx),
                (
                    prop("FilterName", "Office Open XML Text"),
                    prop("Overwrite", True),
                ),
            )
        if target_pdf != "-":
            doc.storeToURL(
                file_url(target_pdf),
                (
                    prop("FilterName", "writer_pdf_Export"),
                    prop("Overwrite", True),
                ),
            )
        return 0
    finally:
        if doc is not None:
            try:
                doc.close(True)
            except Exception:
                try:
                    doc.dispose()
                except Exception:
                    pass
        if desktop is not None:
            try:
                desktop.terminate()
            except Exception:
                pass
        try:
            proc.terminate()
            proc.wait(timeout=10)
        except Exception:
            try:
                proc.kill()
            except Exception:
                pass


if __name__ == "__main__":
    sys.exit(main())
