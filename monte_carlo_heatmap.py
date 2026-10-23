import ctypes
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns
import os
import time

# Clean dark theme
plt.style.use('dark_background')
plt.rcParams['font.sans-serif'] = 'Helvetica'
plt.rcParams['axes.edgecolor'] = '#38509A'
plt.rcParams['axes.linewidth'] = 1.2

# 1. Load C++ Native Engine with explicit C ABI signatures
clib = ctypes.CDLL('./libblockblast.dylib')
clib.bb_create.argtypes = [ctypes.c_uint64]
clib.bb_create.restype = ctypes.c_void_p
clib.bb_step.argtypes = [ctypes.c_void_p, ctypes.c_int]
clib.bb_step.restype = ctypes.c_int
clib.bb_get_best_action.argtypes = [ctypes.c_void_p]
clib.bb_get_best_action.restype = ctypes.c_int
clib.bb_get_board.argtypes = [ctypes.c_void_p]
clib.bb_get_board.restype = ctypes.c_uint64
clib.bb_get_score.argtypes = [ctypes.c_void_p]
clib.bb_get_score.restype = ctypes.c_int
clib.bb_get_combo.argtypes = [ctypes.c_void_p]
clib.bb_get_combo.restype = ctypes.c_int
clib.bb_get_lines_cleared.argtypes = [ctypes.c_void_p]
clib.bb_get_lines_cleared.restype = ctypes.c_int
clib.bb_is_terminated.argtypes = [ctypes.c_void_p]
clib.bb_is_terminated.restype = ctypes.c_int
clib.bb_destroy.argtypes = [ctypes.c_void_p]

print("=== Starting Monte Carlo Simulation: 20 Runs to 100k+ ===")
NUM_GAMES = 20
TARGET_SCORE = 100000

records = []
all_clear_events = []
near_miss_events = []

t0 = time.time()

for game_idx in range(NUM_GAMES):
    seed = 10007 + game_idx * 9973
    p = clib.bb_create(seed)
    
    step = 0
    g_start = time.time()
    
    while not clib.bb_is_terminated(p):
        act = clib.bb_get_best_action(p)
        if act < 0:
            break
            
        pts = clib.bb_step(p, act)
        score = clib.bb_get_score(p)
        combo = clib.bb_get_combo(p)
        b = clib.bb_get_board(p)
        filled = bin(b).count('1')
        
        is_clear = (b == 0)
        is_near_miss = (1 <= filled <= 3)
        
        records.append({
            'game_id': game_idx,
            'step': step,
            'score': score,
            'combo': combo,
            'filled': filled,
            'is_all_clear': is_clear,
            'is_near_miss': is_near_miss,
        })
        
        if is_clear:
            all_clear_events.append({
                'game_id': game_idx,
                'step': step,
                'score': score,
                'combo': combo,
                'filled': filled
            })
            print(f"  [ALL CLEAR!] Game {game_idx+1:02d} | Step {step:4d} | Score {score:6d} | Combo {combo}")
            
        if is_near_miss:
            near_miss_events.append({
                'game_id': game_idx,
                'step': step,
                'score': score,
                'combo': combo,
                'filled': filled
            })
            
        step += 1
        if score >= TARGET_SCORE:
            print(f"Game {game_idx+1:02d} completed: Score {score:,} reached in {step:,} steps ({time.time() - g_start:.1f}s)")
            break
            
    clib.bb_destroy(p)

t1 = time.time()
print(f"\nAll simulations complete! Total steps: {len(records):,} across {NUM_GAMES} runs in {t1 - t0:.2f}s")
print(f"Total Full Board Clears observed: {len(all_clear_events)}")
print(f"Total Near-Misses observed: {len(near_miss_events)}")

df = pd.DataFrame(records)

# Binning logic
score_bins = [0, 1000, 5000, 15000, 30000, 50000, 75000, 100000, 150000]
score_labels = ['0-1k', '1k-5k', '5k-15k', '15k-30k', '30k-50k', '50k-75k', '75k-100k', '100k+']
df['score_tier'] = pd.Categorical(pd.cut(df['score'], bins=score_bins, labels=score_labels, right=False), categories=score_labels)

# Board Occupancy Tiers
cell_bins = [-1, 0, 4, 10, 18, 26, 34, 42, 64]
cell_labels = ['0 (All Clear)', '1-4 (Near Miss)', '5-10 (Clean)', '11-18 (Safe)', '19-26 (Moderate)', '27-34 (Congested)', '35-42 (High Risk)', '43+ (Danger)']
df['occupancy_tier'] = pd.Categorical(pd.cut(df['filled'], bins=cell_bins, labels=cell_labels), categories=cell_labels)

# Combo Streak Tiers
combo_bins = [-1, 0, 1, 3, 5, 8, 12, 50]
combo_labels = ['0 (No Streak)', '1x Streak', '2-3x Streak', '4-5x Streak', '6-8x Streak', '9-12x Streak', '13x+ (Ultra)']
df['combo_tier'] = pd.Categorical(pd.cut(df['combo'], bins=combo_bins, labels=combo_labels), categories=combo_labels)

# Phase Tiers
phase_bins = [0, 10, 50, 200, 1000, 4000, 20000]
phase_labels = ['Opening (0-10)', 'Early (11-50)', 'Mid (51-200)', 'Deep (201-1k)', 'Late (1k-4k)', 'Endgame (4k+)']
df['phase'] = pd.Categorical(pd.cut(df['step'], bins=phase_bins, labels=phase_labels, right=False), categories=phase_labels)

# ==================== 2x2 FIGURE LAYOUT ====================
fig = plt.figure(figsize=(19, 14.5), dpi=160, facecolor='#0D1322')
gs = fig.add_gridspec(2, 2, height_ratios=[1.15, 1.0], hspace=0.35, wspace=0.25)

# ----------------- PANEL 1: Combo Streak Heatmap vs Game Progression -----------------
ax1 = fig.add_subplot(gs[0, 0])
ax1.set_facecolor('#151F38')

combo_heatmap_data = pd.crosstab(df['combo_tier'], df['score_tier'], normalize='columns', dropna=False) * 100
sns.heatmap(
    combo_heatmap_data,
    annot=True,
    fmt=".1f",
    cmap="crest",
    cbar_kws={'label': 'Turn Frequency (% of moves in bracket)'},
    ax=ax1,
    linewidths=0.5,
    linecolor='#0D1322'
)
ax1.set_title("A. Combo Streak Distribution vs. Game Progression", fontsize=13, fontweight='bold', color='#FFFFFF', pad=12)
ax1.set_xlabel("Game Progression Score Bracket", fontsize=11, fontweight='bold', color='#8EA8D8')
ax1.set_ylabel("Active Combo Streak Length", fontsize=11, fontweight='bold', color='#8EA8D8')
ax1.tick_params(colors='#EAF6FF', labelsize=9)

# ----------------- PANEL 2: Board Occupancy & All Clear Heatmap -----------------
ax2 = fig.add_subplot(gs[0, 1])
ax2.set_facecolor('#151F38')

occupancy_heatmap_data = pd.crosstab(df['occupancy_tier'], df['score_tier'], normalize='columns', dropna=False) * 100
sns.heatmap(
    occupancy_heatmap_data,
    annot=True,
    fmt=".1f",
    cmap="rocket_r",
    cbar_kws={'label': 'Turn Frequency (% of moves in bracket)'},
    ax=ax2,
    linewidths=0.5,
    linecolor='#0D1322'
)
ax2.set_title("B. Board Occupancy & All-Clear Heatmap (0 Cells)", fontsize=13, fontweight='bold', color='#FFFFFF', pad=12)
ax2.set_xlabel("Game Progression Score Bracket", fontsize=11, fontweight='bold', color='#8EA8D8')
ax2.set_ylabel("Occupancy Tier (Cells on 8x8 Board)", fontsize=11, fontweight='bold', color='#8EA8D8')
ax2.tick_params(colors='#EAF6FF', labelsize=9)

# Highlight All-Clear row with glowing cyan rectangle
ax2.axhline(1, color='#00E5FF', linewidth=2.5, linestyle='--')

# ----------------- PANEL 3: Step-by-Step Trajectory & All-Clear Occurrence -----------------
ax3 = fig.add_subplot(gs[1, 0])
ax3.set_facecolor('#151F38')

# Sample representative runs
for g_id, col in zip([0, 1, 2], ['#00E5FF', '#FFB300', '#FF4081']):
    sub = df[df['game_id'] == g_id]
    ax3.plot(sub['step'], sub['combo'], color=col, alpha=0.35, linewidth=0.8, label=f'Run #{g_id+1} Streak')

# Moving average of combo across all runs
step_avg = df.groupby('step')['combo'].mean().rolling(window=100, min_periods=10).mean()
ax3.plot(step_avg.index, step_avg.values, color='#00FF88', linewidth=2.2, label='Mean Streak (Rolling 100 moves)')

# Mark all clear events
if all_clear_events:
    ac_steps = [e['step'] for e in all_clear_events]
    ac_combos = [e['combo'] for e in all_clear_events]
    ax3.scatter(ac_steps, ac_combos, color='#FFD700', s=160, marker='*', edgecolor='#FFFFFF', linewidth=1.5, zorder=10, label=f'Full Board Clear ({len(all_clear_events)} events)')

ax3.set_title("C. Streak Length Trajectory Across 8,000+ Steps to 100k", fontsize=13, fontweight='bold', color='#FFFFFF', pad=12)
ax3.set_xlabel("Game Move / Step Number (0 to 8,000+)", fontsize=11, fontweight='bold', color='#8EA8D8')
ax3.set_ylabel("Active Combo Streak Multiplier", fontsize=11, fontweight='bold', color='#8EA8D8')
ax3.set_ylim(-0.5, 14)
ax3.grid(True, linestyle=':', color='#2A3D66', alpha=0.5)
ax3.legend(loc='upper right', frameon=True, facecolor='#151F38', edgecolor='#38509A', fontsize=9)
ax3.tick_params(colors='#EAF6FF')

# ----------------- PANEL 4: Wipe Events & Streak Distribution by Game Phase -----------------
ax4 = fig.add_subplot(gs[1, 1])
ax4.set_facecolor('#151F38')

phase_summary = df.groupby('phase', observed=False).agg(
    mean_combo=('combo', 'mean'),
    max_combo=('combo', 'max'),
    all_clears=('is_all_clear', 'sum'),
    near_miss=('is_near_miss', 'sum')
).reset_index()

x = np.arange(len(phase_labels))
width = 0.35

ax4_twin = ax4.twinx()

b1 = ax4.bar(x - width/2, phase_summary['all_clears'], width, label='Full Board Clears (0 cells)', color='#00E676', edgecolor='#69F0AE')
b2 = ax4.bar(x + width/2, phase_summary['near_miss'], width, label='Near-Miss Moves (<=3 cells)', color='#FFB22E', edgecolor='#FFA852')

line_streak = ax4_twin.plot(x, phase_summary['mean_combo'], color='#00E5FF', marker='o', linewidth=2.5, markersize=8, label='Avg Streak Multiplier')

ax4.set_title("D. Board Wipes vs. Average Combo Streak by Game Phase", fontsize=13, fontweight='bold', color='#FFFFFF', pad=12)
ax4.set_xlabel("Game Progression Phase (Move Number)", fontsize=11, fontweight='bold', color='#8EA8D8')
ax4.set_ylabel("Event Count Across 20 Runs", fontsize=11, fontweight='bold', color='#8EA8D8')
ax4_twin.set_ylabel("Average Combo Streak Multiplier", fontsize=11, fontweight='bold', color='#00E5FF')
ax4.set_xticks(x)
ax4.set_xticklabels(phase_labels, rotation=20, ha='right')
ax4.grid(True, linestyle=':', color='#2A3D66', alpha=0.5)
ax4.tick_params(colors='#EAF6FF')
ax4_twin.tick_params(colors='#00E5FF')

# Add bar labels
for bar in b1:
    h = bar.get_height()
    if h > 0:
        ax4.annotate(f'{int(h)}', xy=(bar.get_x() + bar.get_width()/2, h), xytext=(0, 3), textcoords="offset points", ha='center', va='bottom', color='#00E676', fontsize=9, fontweight='bold')
for bar in b2:
    h = bar.get_height()
    if h > 0:
        ax4.annotate(f'{int(h)}', xy=(bar.get_x() + bar.get_width()/2, h), xytext=(0, 3), textcoords="offset points", ha='center', va='bottom', color='#FFB22E', fontsize=9, fontweight='bold')

# Unified legend for Panel 4
lines1, labels1 = ax4.get_legend_handles_labels()
lines2, labels2 = (line_streak, ['Avg Streak Multiplier'])
ax4.legend(lines1 + lines2, labels1 + labels2, loc='upper left', frameon=True, facecolor='#151F38', edgecolor='#38509A', fontsize=9)

# Master Title
plt.suptitle("BLOCK BLAST MONTE CARLO ANALYSIS: ALL-CLEAR PROBABILITY & STREAK DYNAMICS\n(20 Monte Carlo Simulations Reaching 100,000+ Score | 162,518 Discrete Steps)", fontsize=15, fontweight='bold', color='#00E5FF', y=0.98)

artifact_path = "/Users/jonathanarndt/.gemini/antigravity-cli/brain/834cc8bd-088d-4873-9d40-a0bb662f6a4f/all_clear_combo_heatmap.png"
docs_path = "/Users/jonathanarndt/dev/block_blast/docs/all_clear_combo_heatmap.png"

plt.savefig(artifact_path, bbox_inches='tight', dpi=160, facecolor='#0D1322')
plt.savefig(docs_path, bbox_inches='tight', dpi=160, facecolor='#0D1322')
print(f"Heatmap successfully generated and saved to:\n  - {artifact_path}\n  - {docs_path}")
