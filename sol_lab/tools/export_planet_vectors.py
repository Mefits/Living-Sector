#!/usr/bin/env python3
"""Export editable SVG planet sources as two fixed Godot-friendly PNG sizes.

Usage: python sol_lab/tools/export_planet_vectors.py
Dependency: pip install cairosvg
"""
from pathlib import Path
import cairosvg

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / 'assets' / 'planets_svg'
DESTINATION = ROOT / 'assets' / 'planets'
PILOT = [('sol', 'earth'), ('sol', 'saturn'), ('biomes', 'desert_world')]
SIZES = [('map_icons', 32), ('planets', 512)]


def main():
    for group, name in PILOT:
        source = SOURCES / group / f'{name}.svg'
        for folder, side in SIZES:
            destination = DESTINATION / group / folder / f'{name}_vector.png'
            destination.parent.mkdir(parents=True, exist_ok=True)
            cairosvg.svg2png(url=str(source), write_to=str(destination),
                            output_width=side, output_height=side)
            print(f'{destination.relative_to(ROOT)}: {side}x{side}')


if __name__ == '__main__':
    main()
