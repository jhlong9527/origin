"""Compatibility entry point for the complete high-detail Blender rig builder."""
import runpy
from pathlib import Path

runpy.run_path(str(Path(__file__).with_name('build_rigged_hero.py')),run_name='__main__')
