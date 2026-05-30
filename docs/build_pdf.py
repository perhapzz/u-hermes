"""Render docs/U-Hermes 使用文档.md to PDF via Edge headless.

Pipeline: Markdown -> styled HTML -> Edge --print-to-pdf -> PDF.
"""
from __future__ import annotations

import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import markdown

HERE = Path(__file__).parent
REPO_ROOT = HERE.parent
MD = HERE / "U-Hermes 使用文档.md"
PDF = REPO_ROOT / "U-Hermes 使用文档.pdf"

CSS = r"""
@page {
  size: A4;
  margin: 18mm 18mm 22mm 18mm;
  @bottom-center {
    content: "U-Hermes 使用文档 · 第 " counter(page) " 页 / 共 " counter(pages) " 页";
    font-family: "Microsoft YaHei", "PingFang SC", sans-serif;
    font-size: 9pt;
    color: #888;
  }
}
:root {
  --fg: #24292f;
  --muted: #6b7280;
  --accent: #0969da;
  --rule: #d0d7de;
  --code-bg: #f6f8fa;
  --quote-fg: #57606a;
}
* { box-sizing: border-box; }
html, body {
  margin: 0;
  padding: 0;
  font-family: "Microsoft YaHei", "PingFang SC", "Helvetica Neue", Arial, sans-serif;
  font-size: 10.5pt;
  line-height: 1.65;
  color: var(--fg);
  -webkit-font-smoothing: antialiased;
}

/* H2 is used for the top-level numbered sections (1./2./3./...).
   Force each one onto a new page so the table of contents reads cleanly. */
h2 {
  font-size: 20pt;
  font-weight: 700;
  color: var(--accent);
  margin: 0 0 0.6em;
  padding-bottom: 0.3em;
  border-bottom: 2px solid var(--accent);
  page-break-before: always;
  page-break-after: avoid;
}
h3 {
  font-size: 14pt;
  font-weight: 700;
  color: var(--fg);
  margin: 1.4em 0 0.4em;
  padding-bottom: 0.15em;
  border-bottom: 1px solid var(--rule);
  page-break-after: avoid;
}
h4 {
  font-size: 11.5pt;
  font-weight: 600;
  margin: 1em 0 0.35em;
  color: var(--muted);
  page-break-after: avoid;
}
/* H1 is the document title — only used on cover, suppressed in body. */
h1 { display: none; }

p, ul, ol { margin: 0.5em 0 0.8em; }
ul, ol { padding-left: 1.6em; }
li { margin: 0.25em 0; }
a { color: var(--accent); text-decoration: none; }
a:hover { text-decoration: underline; }
strong { font-weight: 700; }
hr {
  border: none;
  border-top: 1px solid var(--rule);
  margin: 1.5em 0;
}

blockquote {
  margin: 0.9em 0;
  padding: 0.5em 1em;
  border-left: 3px solid var(--accent);
  background: #f0f6ff;
  color: var(--quote-fg);
  page-break-inside: avoid;
  border-radius: 0 4px 4px 0;
}
blockquote p { margin: 0.3em 0; }
blockquote strong { color: var(--accent); }

code {
  font-family: "Consolas", "Cascadia Code", "Courier New", monospace;
  font-size: 0.92em;
  background: var(--code-bg);
  padding: 1px 5px;
  border-radius: 3px;
  border: 1px solid #e7eaef;
}
pre {
  background: var(--code-bg);
  border: 1px solid #e7eaef;
  border-radius: 6px;
  padding: 12px 14px;
  font-size: 9.5pt;
  line-height: 1.5;
  overflow-x: auto;
  page-break-inside: avoid;
  margin: 0.8em 0;
}
pre code {
  background: transparent;
  padding: 0;
  border: 0;
  font-size: inherit;
}

table {
  border-collapse: collapse;
  margin: 1em 0;
  width: 100%;
  font-size: 0.95em;
  page-break-inside: avoid;
}
th, td {
  border: 1px solid var(--rule);
  padding: 6px 10px;
  text-align: left;
  vertical-align: top;
}
th { background: #f6f8fa; font-weight: 600; }
tr:nth-child(2n) td { background: #fafbfc; }

/* Cover page */
.cover {
  height: 240mm;
  display: flex;
  flex-direction: column;
  justify-content: center;
  align-items: center;
  text-align: center;
}
.cover .title {
  font-size: 48pt;
  font-weight: 700;
  color: var(--accent);
  margin: 0 0 8pt 0;
  letter-spacing: 2px;
}
.cover .subtitle {
  font-size: 16pt;
  margin: 8pt 0 28pt 0;
}
.cover .tagline {
  font-size: 12pt;
  color: var(--muted);
  margin: 0 0 80pt 0;
}
.cover .meta { font-size: 11pt; color: var(--muted); }
.cover .meta span { margin: 0 6pt; }
"""

COVER_HTML = """
<div class="cover">
  <div class="title">U-Hermes</div>
  <div class="subtitle">便携式 AI Agent · 使用文档</div>
  <div class="tagline">插上 U 盘就能用 · 无需安装 · 无残留</div>
  <div class="meta"><span>版本 0.1</span>·<span>2026-05</span></div>
</div>
"""


def find_browser() -> str:
    candidates = [
        os.environ.get("EDGE_PATH"),
        r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
        r"C:\Program Files\Microsoft\Edge\Application\msedge.exe",
        r"C:\Program Files\Google\Chrome\Application\chrome.exe",
        r"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
        shutil.which("msedge"),
        shutil.which("chrome"),
    ]
    for c in candidates:
        if c and Path(c).exists():
            return c
    raise FileNotFoundError("Could not locate Edge or Chrome. Set EDGE_PATH env var.")


def main() -> int:
    if not MD.exists():
        print(f"Source markdown not found: {MD}", file=sys.stderr)
        return 1

    md_text = MD.read_text(encoding="utf-8")

    # Strip the document-title block (everything up to & including the first
    # horizontal rule) — that material lives on the cover page instead.
    lines = md_text.splitlines()
    stripped: list[str] = []
    in_intro = True
    for line in lines:
        if in_intro:
            if line.strip().startswith("---"):
                in_intro = False
            continue
        stripped.append(line)
    md_body = "\n".join(stripped).lstrip()

    html_body = markdown.markdown(
        md_body,
        extensions=["extra", "sane_lists", "admonition", "toc", "codehilite"],
        extension_configs={
            "codehilite": {
                "css_class": "highlight",
                "guess_lang": False,
                "noclasses": True,
            }
        },
        output_format="html5",
    )

    full_html = f"""<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<title>U-Hermes 使用文档</title>
<style>{CSS}</style>
</head>
<body>
{COVER_HTML}
{html_body}
</body>
</html>"""

    with tempfile.TemporaryDirectory(prefix="uhermes-pdf-") as tmp:
        tmp_html = Path(tmp) / "doc.html"
        tmp_html.write_text(full_html, encoding="utf-8")

        browser = find_browser()
        cmd = [
            browser,
            "--headless=new",
            "--disable-gpu",
            "--no-pdf-header-footer",
            f"--print-to-pdf={PDF}",
            tmp_html.as_uri(),
        ]
        print(f"Rendering via: {Path(browser).name}")
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
        if result.returncode != 0:
            print("Browser stderr:", result.stderr, file=sys.stderr)
            return result.returncode

    if not PDF.exists():
        print("PDF not produced. Browser may have failed silently.", file=sys.stderr)
        return 2
    size_kb = PDF.stat().st_size // 1024
    print(f"OK -> {PDF.name}  ({size_kb} KB)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
