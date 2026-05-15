#!/usr/bin/env python3
import struct
from pathlib import Path


TRANSLATIONS = {
    "zh_CN": {
        "Applications": "应用",
        "Places": "文件",
    },
    "en_US": {
        "Applications": "Apps",
        "Places": "Files",
    },
    "ja_JP": {
        "Applications": "アプリ",
        "Places": "ファイル",
    },
    "es_ES": {
        "Applications": "Apps",
        "Places": "Archivos",
    },
    "pt_BR": {
        "Applications": "Apps",
        "Places": "Arquivos",
    },
    "ko_KR": {
        "Applications": "앱",
        "Places": "파일",
    },
    "de_DE": {
        "Applications": "Apps",
        "Places": "Dateien",
    },
}


def write_mo(path, messages):
    catalog = {"": "Content-Type: text/plain; charset=UTF-8\n"}
    catalog.update(messages)

    keys = sorted(catalog)
    ids = [key.encode("utf-8") for key in keys]
    values = [catalog[key].encode("utf-8") for key in keys]
    count = len(keys)

    key_start = 7 * 4 + count * 16
    value_start = key_start + sum(len(item) + 1 for item in ids)

    key_offsets = []
    offset = key_start
    for item in ids:
        key_offsets.append((len(item), offset))
        offset += len(item) + 1

    value_offsets = []
    offset = value_start
    for item in values:
        value_offsets.append((len(item), offset))
        offset += len(item) + 1

    payload = [
        struct.pack("Iiiiiii", 0x950412DE, 0, count, 7 * 4, 7 * 4 + count * 8, 0, 0),
        *(struct.pack("ii", *item) for item in key_offsets),
        *(struct.pack("ii", *item) for item in value_offsets),
        *(item + b"\0" for item in ids),
        *(item + b"\0" for item in values),
    ]

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(b"".join(payload))


def main():
    for locale_name, messages in TRANSLATIONS.items():
        write_mo(Path(f"/usr/share/locale/{locale_name}/LC_MESSAGES/gnome-panel.mo"), messages)


if __name__ == "__main__":
    main()
