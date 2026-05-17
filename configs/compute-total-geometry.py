#!/usr/bin/env python3
import re
import sys

LAYOUT_PATTERN = re.compile(r'^(\d+)x(\d+)\+(\d+)\+(\d+)$')


def main():
    if len(sys.argv) != 2:
        print('1920x1080')
        return 1

    layout = sys.argv[1].strip()
    if not layout:
        print('1920x1080')
        return 1

    total_w = 0
    total_h = 0
    for part in layout.split(','):
        m = LAYOUT_PATTERN.match(part.strip())
        if not m:
            print(f'invalid monitor spec: {part}', file=sys.stderr)
            return 2
        w, h, x, y = map(int, m.groups())
        total_w = max(total_w, x + w)
        total_h = max(total_h, y + h)

    print(f'{total_w}x{total_h}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
