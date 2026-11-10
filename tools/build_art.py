#!/usr/bin/env python3
"""Convert theme paintings and the welcome banner to game textures.

Usage: tools/build_art.py <folder of theme-*.png>
       tools/build_art.py --banner <welcome-banner.png>
"""
import argparse
import glob
import os

from PIL import Image

SIZE = 512
out = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "Textures")
def convert(path, name, size):
    os.makedirs(out, exist_ok=True)
    with Image.open(path) as image:
        image.convert("RGB").resize(size, Image.LANCZOS).save(os.path.join(out, name))
    print(name)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("folder", nargs="?")
    parser.add_argument("--banner")
    args = parser.parse_args()
    if bool(args.folder) == bool(args.banner):
        parser.error("provide a theme folder or --banner")
    if args.banner:
        convert(args.banner, "welcome-banner.tga", (1024, 256))
    else:
        for path in sorted(glob.glob(os.path.join(args.folder, "theme-*.png"))):
            convert(path, os.path.splitext(os.path.basename(path))[0] + ".tga", (SIZE, SIZE))


if __name__ == "__main__":
    main()
