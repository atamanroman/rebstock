#!/usr/bin/env python3
"""Print the readable text of an invoice email.

    parse_eml.py "invoice.eml"

Merchant invoices frequently ship no text/plain part at all — only HTML with
the line items in a table. Dropping tags naively runs product, quantity and
price together, so cell and row ends become separators first.

Output is text for reading, not a parser: read the line items off it yourself.
Plain and HTML alternatives describe the same invoice; do not count them twice.
"""

import email
import email.policy
import html
import re
import sys
from pathlib import Path


def readable_text(markup):
    text = re.sub(r"<(script|style)[^>]*>.*?</\1>", "", markup, flags=re.S | re.I)
    text = re.sub(r"</t[dh]>", "\t", text, flags=re.I)
    text = re.sub(r"<br\s*/?>|</tr>|</p>|</div>|</h[1-6]>", "\n", text, flags=re.I)
    text = re.sub(r"<[^>]+>", "", text)
    text = html.unescape(text)
    text = re.sub(r"[ \t]+\n", "\n", text)
    return re.sub(r"\n{3,}", "\n\n", text)


def main():
    if len(sys.argv) != 2:
        print(__doc__)
        return 1
    with Path(sys.argv[1]).open("rb") as f:
        message = email.message_from_binary_file(f, policy=email.policy.default)

    print(f"Subject: {message['subject']}\nFrom: {message['from']}\nDate: {message['date']}\n")
    for part in message.walk():
        if part.is_attachment():
            print(f"Attachment (inspect separately): {part.get_filename()} ({part.get_content_type()})")

    parts = [p for p in message.walk() if not p.is_attachment()]
    plain = [p for p in parts if p.get_content_type() == "text/plain"]
    markup = [p for p in parts if p.get_content_type() == "text/html"]
    if not plain and not markup:
        print("no text/plain or text/html part; parts: "
              f"{[p.get_content_type() for p in message.walk()]}")
        return 1
    for part in plain:
        print("--- Plain text ---")
        print(part.get_content())
    for part in markup:
        print("--- HTML alternative (same invoice) ---")
        print(readable_text(part.get_content()))
    return 0


if __name__ == "__main__":
    sys.exit(main())
