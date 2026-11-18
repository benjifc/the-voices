#!/usr/bin/env python3
"""Utilidades de release de The Voices: changelog, notas y appcast."""
import html
import re
import sys
from pathlib import Path

REPO_URL = "https://github.com/benjifc/the-voices"
CHANGELOG = Path(__file__).resolve().parent.parent / "CHANGELOG.md"
UNRELEASED = "Sin publicar"
VERSION_RE = re.compile(r"^\d+\.\d+\.\d+$")
HEADING_RE = re.compile(r"^## \[(?P<name>[^\]]+)\](?: - (?P<date>\d{4}-\d{2}-\d{2}))?\s*$")
LINK_RE = re.compile(r"^\[[^\]]+\]: https?://")


def _split(text: str):
    """Devuelve (cabecera, [(nombre, fecha, cuerpo)]) sin las líneas de enlaces finales."""
    lines = [l for l in text.splitlines() if not LINK_RE.match(l)]
    header, sections, current = [], [], None
    for line in lines:
        m = HEADING_RE.match(line)
        if m:
            current = [m["name"], m["date"], []]
            sections.append(current)
        elif current is None:
            header.append(line)
        else:
            current[2].append(line)
    return header, [(n, d, "\n".join(b).strip("\n")) for n, d, b in sections]


def _render(header, sections) -> str:
    out = "\n".join(header).rstrip("\n") + "\n"
    for name, date, body in sections:
        out += f"\n## [{name}]" + (f" - {date}" if date else "") + "\n"
        if body:
            out += "\n" + body + "\n"
    versions = [n for n, _, _ in sections if VERSION_RE.match(n)]
    links = []
    if versions:
        links.append(f"[{UNRELEASED}]: {REPO_URL}/compare/v{versions[0]}...HEAD")
    for i, v in enumerate(versions):
        if i + 1 < len(versions):
            links.append(f"[{v}]: {REPO_URL}/compare/v{versions[i + 1]}...v{v}")
        else:
            links.append(f"[{v}]: {REPO_URL}/releases/tag/v{v}")
    if links:
        out += "\n" + "\n".join(links) + "\n"
    return out


def promote(version: str, date: str) -> None:
    """Convierte «Sin publicar» en la versión indicada y deja una sección nueva vacía."""
    if not VERSION_RE.match(version):
        sys.exit(f"Versión no válida: {version} (se espera MAJOR.MINOR.PATCH)")
    header, sections = _split(CHANGELOG.read_text())
    names = [n for n, _, _ in sections]
    if version in names:
        sys.exit(f"CHANGELOG.md ya tiene la versión {version}")
    if not sections or sections[0][0] != UNRELEASED:
        sys.exit(f"CHANGELOG.md debe empezar por la sección «[{UNRELEASED}]»")
    if not sections[0][2].strip():
        sys.exit(f"La sección «[{UNRELEASED}]» está vacía: describe los cambios antes de publicar")
    new = [(UNRELEASED, None, ""), (version, date, sections[0][2])] + sections[1:]
    CHANGELOG.write_text(_render(header, new))


def notes(version: str) -> str:
    """Notas (Markdown) de una versión."""
    _, sections = _split(CHANGELOG.read_text())
    for name, _, body in sections:
        if name == version:
            return body.strip() + "\n"
    sys.exit(f"CHANGELOG.md no tiene la versión {version}")


def notes_html(version: str) -> str:
    """Notas de una versión como HTML simple para el appcast de Sparkle."""
    out, in_list = [], False
    for raw in notes(version).splitlines():
        line = raw.rstrip()
        if line.startswith("### "):
            if in_list:
                out.append("</ul>")
                in_list = False
            out.append(f"<h3>{html.escape(line[4:])}</h3>")
        elif line.startswith("- "):
            if not in_list:
                out.append("<ul>")
                in_list = True
            out.append(f"<li>{_inline(line[2:])}</li>")
        elif line:
            out.append(f"<p>{_inline(line)}</p>")
    if in_list:
        out.append("</ul>")
    return "\n".join(out)


def _inline(text: str) -> str:
    text = html.escape(text)
    return re.sub(r"`([^`]+)`", r"<code>\1</code>", text)


def appcast(version: str, build: str, pub_date: str, url: str, signature: str, length: str) -> str:
    """appcast.xml de Sparkle con una única entrada (la última versión)."""
    return f"""<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>The Voices</title>
    <link>{REPO_URL}</link>
    <description>Versiones de The Voices</description>
    <language>es</language>
    <item>
      <title>Versión {version}</title>
      <pubDate>{pub_date}</pubDate>
      <sparkle:version>{build}</sparkle:version>
      <sparkle:shortVersionString>{version}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
      <link>{REPO_URL}/releases/tag/v{version}</link>
      <description><![CDATA[
{notes_html(version)}
      ]]></description>
      <enclosure url="{url}" sparkle:edSignature="{signature}" length="{length}" type="application/octet-stream"/>
    </item>
  </channel>
</rss>
"""


def main() -> None:
    cmd, args = (sys.argv[1] if len(sys.argv) > 1 else ""), sys.argv[2:]
    if cmd == "promote" and len(args) == 2:
        promote(*args)
    elif cmd == "notes" and len(args) == 1:
        sys.stdout.write(notes(args[0]))
    elif cmd == "notes-html" and len(args) == 1:
        sys.stdout.write(notes_html(args[0]) + "\n")
    elif cmd == "appcast" and len(args) == 6:
        sys.stdout.write(appcast(*args))
    else:
        sys.exit(
            "uso: release_tools.py promote VERSION FECHA | notes VERSION | notes-html VERSION |"
            " appcast VERSION BUILD PUBDATE URL FIRMA LONGITUD"
        )


if __name__ == "__main__":
    main()
