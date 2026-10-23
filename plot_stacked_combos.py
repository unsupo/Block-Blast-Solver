import json
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns

plt.style.use('dark_background')
plt.rcParams['font.sans-serif'] = 'Helvetica'
plt.rcParams['axes.edgecolor'] = '#38509A'
plt.rcParams['axes.linewidth'] = 1.2

def generate_stacked_combo_chart(json_path='stacked_combos_data.json', out_png='docs/stacked_combos_by_stage.png'):
    with open(json_path, 'r') as f:
        data = json.load(f)

    stage_display = [
        '0 - 500\n(Warmup)',
        '500 - 1.4k\n(DDA T1: 12%)',
        '1.4k - 3.8k\n(DDA T2: 20%)',
        '3.8k - 8.4k\n(DDA T3: 30%)',
        '8.4k - 25k\n(Plateau Entry)',
        '25k - 50k\n(Plateau Mid)',
        '50k - 100k+\n(Plateau Deep)'
    ]
    combo_names = ['Combo 0', 'Combo 1', 'Combo 2', 'Combo 3', 'Combo 4', 'Combo 5', 'Combo 6', 'Combo 7+']

    combo_arr = np.array(data['combo_table']) # shape: (7 stages, 8 combos)
    stage_moves = np.array(data['stage_moves'])
    runs_reached = np.array(data['runs_reached'])
    total_games = data['total_games']
    reach_pct = (runs_reached / total_games) * 100.0

    # Normalize combo table to percentages per stage
    combo_pct = (combo_arr / stage_moves[:, np.newaxis]) * 100.0 # shape (7, 8)

    # Color palette for combos 0 through 7+
    colors = [
        '#223254', # Combo 0: Slate Dark
        '#00B0FF', # Combo 1: Sky Blue
        '#00E676', # Combo 2: Emerald Green
        '#FFD600', # Combo 3: Golden Yellow
        '#FF9100', # Combo 4: Bright Orange
        '#FF3D00', # Combo 5: Crimson Coral
        '#E040FB', # Combo 6: Magenta
        '#7C4DFF'  # Combo 7+: Electric Violet
    ]

    fig = plt.figure(figsize=(20, 16), dpi=160, facecolor='#0D1322')
    gs = fig.add_gridspec(2, 2, height_ratios=[1.25, 1.0], hspace=0.35, wspace=0.25)

    # =========================================================================
    # TOP PANEL: STACKED BAR GRAPH OF COMBOS AT EACH STAGE
    # =========================================================================
    ax1 = fig.add_subplot(gs[0, :])
    ax1.set_facecolor('#151F38')

    x = np.arange(len(stage_display))
    bar_width = 0.58

    bottoms = np.zeros(len(stage_display))

    for c_idx in range(len(combo_names)):
        vals = combo_pct[:, c_idx]
        bars = ax1.bar(x, vals, bar_width, bottom=bottoms, label=combo_names[c_idx],
                       color=colors[c_idx], edgecolor='#0D1322', linewidth=0.8, alpha=0.92)

        # Label inside segment if >= 3%
        for i, val in enumerate(vals):
            if val >= 3.0:
                y_pos = bottoms[i] + val / 2.0
                text_col = '#FFFFFF' if c_idx in [0, 4, 5, 6, 7] else '#0D1322'
                ax1.annotate(f"{val:.1f}%", xy=(x[i], y_pos), ha='center', va='center',
                             color=text_col, fontsize=9, fontweight='bold')
        bottoms += vals

    # Superimpose 100k Reach Rate line on twin axis
    ax1_twin = ax1.twinx()
    line_reach = ax1_twin.plot(x, reach_pct, color='#00FFFF', marker='o', linewidth=3.0, markersize=9,
                              label='100k Reach / Survival Rate (%)', zorder=15)
    ax1_twin.set_ylabel("Runs Reaching Stage (%)", fontsize=11, fontweight='bold', color='#00FFFF')
    ax1_twin.set_ylim(85, 108)
    ax1_twin.tick_params(colors='#00FFFF')

    # Annotate Reach points
    for i, r in enumerate(reach_pct):
        ax1_twin.annotate(f"{r:.1f}%", xy=(x[i], r), xytext=(0, 7), textcoords="offset points",
                          ha='center', va='bottom', color='#00FFFF', fontsize=9, fontweight='bold')

    # Highlight 8.4k DDA Ceiling Boundary
    ax1.axvline(3.5, color='#FF5252', linestyle='--', linewidth=2.5, alpha=0.9, zorder=12)
    ax1.text(3.55, 92.0, "[!] 8,400 SCORE DDA CEILING\n  (Difficulty stops scaling)", color='#FF5252',
             fontsize=10, fontweight='heavy', zorder=15, bbox=dict(boxstyle='round,pad=0.4', facecolor='#0D1322', edgecolor='#FF5252', alpha=0.9))

    ax1.set_title(f"A. STACKED COMBO DISTRIBUTION AT EACH GAME STAGE\n(Empirical Breakdown Across {total_games:,} Runs to 100k | {data['total_moves']:,} Moves)",
                  fontsize=15, fontweight='bold', color='#FFFFFF', pad=40)
    ax1.set_xlabel("Gameplay Stage & DDA Difficulty Tier", fontsize=12, fontweight='bold', color='#8EA8D8', labelpad=10)
    ax1.set_ylabel("Turn Percentage in Stage (%)", fontsize=11, fontweight='bold', color='#8EA8D8')
    ax1.set_xticks(x)
    ax1.set_xticklabels(stage_display, fontsize=10, fontweight='bold')
    ax1.set_ylim(0, 100)
    ax1.grid(True, linestyle=':', color='#2A3D66', alpha=0.4, axis='y')
    ax1.tick_params(colors='#EAF6FF')

    # Combine legends cleanly above plot
    handles1, labels1 = ax1.get_legend_handles_labels()
    handles2, labels2 = ax1_twin.get_legend_handles_labels()
    ax1.legend(handles1 + handles2, labels1 + labels2, loc='lower center', bbox_to_anchor=(0.5, 1.01),
               frameon=True, facecolor='#151F38', edgecolor='#38509A', fontsize=8.5, ncol=5)

    # =========================================================================
    # BOTTOM LEFT: ACTIVE COMBOS (2, 3, 4, 5, 6+) FOCUS GROUPED BARS
    # =========================================================================
    ax2 = fig.add_subplot(gs[1, 0])
    ax2.set_facecolor('#151F38')

    # Focus on active combos: 2, 3, 4, 5, 6+
    active_combo_indices = [2, 3, 4, 5]
    active_labels = ['Combo 2', 'Combo 3', 'Combo 4', 'Combo 5+']

    # Aggregate combo 5, 6, 7+ into "Combo 5+"
    c2 = combo_pct[:, 2]
    c3 = combo_pct[:, 3]
    c4 = combo_pct[:, 4]
    c5_plus = combo_pct[:, 5] + combo_pct[:, 6] + combo_pct[:, 7]

    active_matrix = np.vstack([c2, c3, c4, c5_plus]) # shape (4, 7)

    w = 0.18
    for idx, (c_label, c_col) in enumerate(zip(active_labels, ['#00E676', '#FFD600', '#FF9100', '#E040FB'])):
        offsets = x - 1.5 * w + idx * w
        ax2.bar(offsets, active_matrix[idx], w, label=c_label, color=c_col, edgecolor='#0D1322', alpha=0.9)

    ax2.axvline(3.5, color='#FF5252', linestyle='--', linewidth=2.0, alpha=0.8)
    ax2.set_title("B. Active Multiplier Distribution (Combos 2, 3, 4, 5+)", fontsize=13, fontweight='bold', color='#FFFFFF', pad=12)
    ax2.set_xlabel("Gameplay Stage", fontsize=11, fontweight='bold', color='#8EA8D8')
    ax2.set_ylabel("Stage Turn Share (%)", fontsize=11, fontweight='bold', color='#8EA8D8')
    ax2.set_xticks(x)
    ax2.set_xticklabels([s.split('\n')[0] for s in stage_display], fontsize=9)
    ax2.grid(True, linestyle=':', color='#2A3D66', alpha=0.5)
    ax2.legend(loc='upper right', frameon=True, facecolor='#151F38', edgecolor='#38509A', fontsize=9)
    ax2.tick_params(colors='#EAF6FF')

    # =========================================================================
    # BOTTOM RIGHT: BOARD OCCUPANCY HEATMAP ACROSS DDA STAGES
    # =========================================================================
    ax3 = fig.add_subplot(gs[1, 1])
    ax3.set_facecolor('#151F38')

    occ_arr = np.array(data['occupancy_table']) # shape (7, 8)
    cell_labels = ['0 (All Clear)', '1-4 (Near Miss)', '5-10 (Clean)', '11-18 (Safe)', '19-26 (Moderate)', '27-34 (Congested)', '35-42 (High Risk)', '43+ (Danger)']
    stage_short = ['0-500', '500-1.4k', '1.4k-3.8k', '3.8k-8.4k', '8.4k-25k', '25k-50k', '50k-100k+']

    occ_pct = (occ_arr.T / stage_moves) * 100.0
    df_occ = pd.DataFrame(occ_pct, index=cell_labels, columns=stage_short)

    sns.heatmap(df_occ, annot=True, fmt=".2f", cmap="rocket_r", cbar_kws={'label': 'Turn Frequency (%)'},
                ax=ax3, linewidths=0.5, linecolor='#0D1322')
    ax3.set_title("C. Board Cell Occupancy Across Exact DDA Stages", fontsize=13, fontweight='bold', color='#FFFFFF', pad=12)
    ax3.set_xlabel("DDA Difficulty Stage", fontsize=11, fontweight='bold', color='#8EA8D8')
    ax3.set_ylabel("Occupancy Tier (Cells on Board)", fontsize=11, fontweight='bold', color='#8EA8D8')
    ax3.tick_params(colors='#EAF6FF', labelsize=8)
    ax3.axhline(1, color='#00E5FF', linewidth=2.5, linestyle='--')

    plt.suptitle("BLOCK BLAST: DDA DIFFICULTY SCALING & STACKED COMBO PROGRESSION", fontsize=16, fontweight='bold', color='#00E5FF', y=0.98)

    artifact_path = "/Users/jonathanarndt/.gemini/antigravity-cli/brain/834cc8bd-088d-4873-9d40-a0bb662f6a4f/stacked_combos_by_stage.png"
    plt.savefig(artifact_path, bbox_inches='tight', dpi=160, facecolor='#0D1322')
    plt.savefig(out_png, bbox_inches='tight', dpi=160, facecolor='#0D1322')
    print(f"Stacked combo chart successfully saved to:\n  - {artifact_path}\n  - {out_png}")

if __name__ == '__main__':
    generate_stacked_combo_chart()
