#!/usr/bin/env python3
import sys

def main():
    text = sys.stdin.read()
    out_lines = []
    for line in text.splitlines():
        low = line.lower()
        # Remove common Claude branding lines
        if low.startswith('co-authored-by: claude') or low.startswith('coauthored-by: claude'):
            continue
        if 'claude code' in low:
            continue
        out_lines.append(line)

    # Collapse trailing blank lines to at most one
    while len(out_lines) >= 2 and out_lines[-1] == '' and out_lines[-2] == '':
        out_lines.pop()

    sys.stdout.write("\n".join(out_lines) + "\n")

if __name__ == '__main__':
    main()

