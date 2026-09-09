# Original surface library

Created procedurally for this project, 2026-09-08. No third-party images.
Each of soil, stone, bark, leaf, metal and cloth has an albedo, tangent-normal and
roughness source map at 512×512. Rebuild with `tools/build_surface_textures.py`.

Runtime use:
- Ground: soil color and normal, world-space blend with painted moss.
- Stone / timber / mushrooms: world-space triplanar color detail and roughness by material family.
- Folded leaves: authored leaf UVs with painted midrib and secondary veins, wind deformation.
- Both characters: local triplanar color, normal and roughness; separate cloth/armor material copies.

Unused normal/roughness variants are retained as editable source maps for future tuning.
The original model vertex palette remains the source of each character's colors.

V4 adds six 1024×1024 neutral maple and petal maps (albedo, normal, roughness).
Rebuild these with `tools/build_maple_textures.py` (NumPy and Pillow). Their
material colors come from geometry / MultiMesh vertex tints. Actual maple
silhouettes are modeled, so no transparent rectangular cards are required.
Mipmaps are enabled in their `.png.import` settings to reduce distant shimmer.
These maps are used by both the red crowns and the 90 pooled drifting leaves;
the original 512×512 green leaf materials are retained for the green forest.
