#!/usr/bin/env python3
import sys
import xml.etree.ElementTree as ET
from pathlib import Path


def prune_file(xml_path, blocked_names):
    try:
        tree = ET.parse(xml_path)
    except ET.ParseError:
        return 0

    root = tree.getroot()
    removed = 0
    for wallpaper in list(root):
        filename = wallpaper.findtext("filename") or wallpaper.findtext("filename-dark") or ""
        if Path(filename).name in blocked_names:
            root.remove(wallpaper)
            removed += 1

    if removed:
        tree.write(xml_path, encoding="UTF-8", xml_declaration=True)
    return removed


def main():
    if len(sys.argv) < 3:
        print("Usage: prune-gnome-backgrounds.py <xml-dir> <filename>...", file=sys.stderr)
        return 2

    xml_dir = Path(sys.argv[1])
    blocked_names = set(sys.argv[2:])
    total = 0
    for xml_path in xml_dir.glob("*.xml"):
        total += prune_file(xml_path, blocked_names)

    print(f"Removed {total} GNOME background entr{'y' if total == 1 else 'ies'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
