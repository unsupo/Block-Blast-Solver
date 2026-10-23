import json

with open("shapes.json") as f:
    shapes = json.load(f)

md_lines = [
    "# Block Blast 43 Reverse-Engineered Shapes Catalog",
    "",
    "Extracted directly from `AlgorithmCore::g_arrShape` in `libtask.so` (`com.block.juggle`).",
    "",
    "| ID | Fill | Size (W x H) | Kind | Visual Grid | Masks (Hex / Dec) |",
    "| :---: | :---: | :---: | :---: | :--- | :--- |"
]

for s in shapes:
    sid = s["id"]
    fill = s["fill"]
    w, h = s["w"], s["h"]
    kind = s["kind"]
    masks = s["masks"]
    
    grid_rows = []
    for r in range(h):
        m = masks[r]
        row_str = "".join("■" if (m & (1 << (w - 1 - c))) else "·" for c in range(w))
        grid_rows.append(row_str)
    grid_html = "<br>".join(f"<code>{r}</code>" for r in grid_rows)
    mask_str = ", ".join(f"0x{m:02X}" for m in masks)
    
    md_lines.append(f"| {sid} | {fill} | {w}x{h} | {kind} | {grid_html} | <code>[{mask_str}]</code> |")

md_lines.append("")
md_lines.append("## Detailed Visual Catalog")
md_lines.append("")

for s in shapes:
    sid = s["id"]
    fill = s["fill"]
    w, h = s["w"], s["h"]
    kind = s["kind"]
    masks = s["masks"]
    
    md_lines.append(f"### Shape {sid}")
    md_lines.append(f"- **Dimensions**: {w} (width) x {h} (height)")
    md_lines.append(f"- **Fill Count**: {fill} cells")
    md_lines.append(f"- **Kind Category**: {kind}")
    md_lines.append(f"- **Row Bitmasks**: `{masks}`")
    md_lines.append("```text")
    for r in range(h):
        m = masks[r]
        row_str = " ".join("■" if (m & (1 << (w - 1 - c))) else "·" for c in range(w))
        md_lines.append(f"  {row_str}")
    md_lines.append("```")
    md_lines.append("")

with open("docs/SHAPES_CATALOG.md", "w") as f:
    f.write("\n".join(md_lines))

print("Successfully written docs/SHAPES_CATALOG.md")
