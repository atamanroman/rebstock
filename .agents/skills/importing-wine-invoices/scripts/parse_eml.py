#!/usr/bin/env python3
"""Print the readable text of an invoice email.

    parse_eml.py "invoice.eml"

Merchant invoices frequently ship no text/plain part at all — only HTML with
the line items in a table. Dropping tags naively runs product, quantity and
price together, so cell and row ends become separators first.

Output is text for reading, not a parser: read the line items off it yourself.
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
    with Path(sys.argv[1]).open(encoding="utf-8", errors="replace") as f:
        message = email.message_from_file(f, policy=email.policy.default)

    print(f"Subject: {message['subject']}\nFrom: {message['from']}\nDate: {message['date']}\n")

    plain = [p for p in message.walk() if p.get_content_type() == "text/plain"]
    markup = [p for p in message.walk() if p.get_content_type() == "text/html"]
    if plain:
        print(plain[0].get_content())
    elif markup:
        print(readable_text(markup[0].get_content()))
    else:
        print("no text/plain or text/html part; parts: "
              f"{[p.get_content_type() for p in message.walk()]}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
