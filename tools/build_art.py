#!/usr/bin/env python3
"""Convert the theme paintings to the TGAs the quiz window loads.

Usage: tools/build_art.py <folder of theme-*.png>
"""
import glob
import os
import sys

from PIL import Image

SIZE = 512
out = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "Textures")
for path in sorted(glob.glob(os.path.join(sys.argv[1], "theme-*.png"))):
    name = os.path.splitext(os.path.basename(path))[0] + ".tga"
    Image.open(path).convert("RGB").resize((SIZE, SIZE), Image.LANCZOS).save(os.path.join(out, name))
    print(name)
