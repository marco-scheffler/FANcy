#!/usr/bin/env python3
"""Add one release to appcast.xml — the feed installed copies of FANcy read to
learn that something newer exists.

Why by hand instead of Sparkle's `generate_appcast`: that tool rebuilds the whole
feed from a folder of archives with *one* shared URL prefix. On GitHub every
release lives under its own tag path (…/releases/download/v1.3.0/…), which a
single prefix can't express. So: one item per call, with exactly the URL the
DMG is uploaded to.

Signing happens in `sign_update`, not here — the private key lives in the
Keychain and has no business in a script. Signature and length come in as
arguments.

Called from native/package.sh:

    native/appcast.py --version 1.3.0 --build 4 --signature <edSignature> \\
        --length 4711 --tag v1.3.0 --dmg-name FANcy-1.3.0.dmg \\
        --notes-file docs/release-notes/1.3.0.html
"""

import argparse
import datetime
import os
import sys
import xml.etree.ElementTree as ET

SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"
REPO_URL = "https://github.com/marco-scheffler/FANcy"
FEED_URL = "https://raw.githubusercontent.com/marco-scheffler/FANcy/main/appcast.xml"

ET.register_namespace("sparkle", SPARKLE_NS)


def empty_feed() -> ET.Element:
    # Don't add the xmlns:sparkle attribute by hand: register_namespace above
    # writes it during serialization. Doing both yields a duplicate attribute on
    # <rss> — a file that gets written but that no parser (including the next
    # run of this script) can read back.
    rss = ET.Element("rss", {"version": "2.0"})
    channel = ET.SubElement(rss, "channel")
    ET.SubElement(channel, "title").text = "FANcy"
    ET.SubElement(channel, "link").text = FEED_URL
    ET.SubElement(channel, "description").text = "FANcy updates"
    ET.SubElement(channel, "language").text = "en"
    return rss


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--appcast", default="appcast.xml")
    p.add_argument("--version", required=True, help="CFBundleShortVersionString, e.g. 1.3.0")
    p.add_argument("--build", required=True, help="CFBundleVersion — the number Sparkle compares")
    p.add_argument("--signature", required=True, help="sparkle:edSignature from sign_update")
    p.add_argument("--length", required=True, help="DMG size in bytes")
    p.add_argument("--tag", required=True, help="git tag of the release, e.g. v1.3.0")
    p.add_argument("--dmg-name", required=True)
    p.add_argument("--minimum-system-version", default="13.0")
    p.add_argument("--notes-file", help="HTML snippet embedded as the release notes")
    args = p.parse_args()

    if os.path.exists(args.appcast):
        rss = ET.parse(args.appcast).getroot()
    else:
        rss = empty_feed()

    channel = rss.find("channel")
    if channel is None:
        print(f"ERROR: {args.appcast} has no <channel>", file=sys.stderr)
        return 1

    # A build may appear only once. Two items with the same build number aren't
    # a double hint — they're a feed where nobody can tell which signature holds.
    for item in channel.findall("item"):
        existing = item.find(f"{{{SPARKLE_NS}}}version")
        if existing is not None and existing.text == args.build:
            print(f"ERROR: build {args.build} is already in the appcast — "
                  "bump CFBundleVersion in native/Resources/Info.plist.", file=sys.stderr)
            return 1

    item = ET.Element("item")
    ET.SubElement(item, "title").text = args.version
    ET.SubElement(item, "pubDate").text = datetime.datetime.now(
        datetime.timezone.utc
    ).strftime("%a, %d %b %Y %H:%M:%S +0000")
    ET.SubElement(item, f"{{{SPARKLE_NS}}}version").text = args.build
    ET.SubElement(item, f"{{{SPARKLE_NS}}}shortVersionString").text = args.version
    # Without this Sparkle would offer the update to a Mac that can't run it.
    ET.SubElement(item, f"{{{SPARKLE_NS}}}minimumSystemVersion").text = args.minimum_system_version

    # Notes are embedded, not linked: Sparkle loads a releaseNotesLink into a
    # small web view, and a GitHub release page shows up there as header, nav
    # and sign-in button with the actual notes scrolled out of sight.
    if args.notes_file:
        with open(args.notes_file, encoding="utf-8") as f:
            ET.SubElement(item, "description").text = f.read().strip()
    else:
        print(f"WARNING: no release notes for {args.version} — the update window "
              "will show the GitHub page instead.", file=sys.stderr)
        ET.SubElement(item, f"{{{SPARKLE_NS}}}releaseNotesLink").text = \
            f"{REPO_URL}/releases/tag/{args.tag}"

    ET.SubElement(item, "enclosure", {
        "url": f"{REPO_URL}/releases/download/{args.tag}/{args.dmg_name}",
        "length": args.length,
        "type": "application/octet-stream",
        f"{{{SPARKLE_NS}}}edSignature": args.signature,
    })

    # Newest first — Sparkle reads the whole feed, but a human skimming the
    # diff reads from the top.
    first = channel.find("item")
    channel.insert(list(channel).index(first) if first is not None else len(channel), item)

    ET.indent(rss, space="  ")
    ET.ElementTree(rss).write(args.appcast, encoding="utf-8", xml_declaration=True)
    # write() adds no trailing newline; without one every diff ends in
    # "\ No newline at end of file".
    with open(args.appcast, "a", encoding="utf-8") as f:
        f.write("\n")

    print(f"▸ {args.version} (build {args.build}) added to {args.appcast}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
