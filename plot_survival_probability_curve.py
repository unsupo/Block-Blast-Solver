import numpy as np
import matplotlib.pyplot as plt
import os

# Clean dark theme
plt.style.use('dark_background')
plt.rcParams['font.sans-serif'] = 'Helvetica'
plt.rcParams['axes.edgecolor'] = '#38509A'
plt.rcParams['axes.linewidth'] = 1.2

def generate_survival_chart(out_png='docs/survival_probability_curve.png'):
    # Empirical hazard rate from 500-game / 4M-move simulation
    # 6 deaths in 3,997,784 moves
    lambda_optimal = 6.0 / 3997784.0 # ~1.5008e-6 deaths/move
    points_per_move = 12.5 # Average empirical points/move in high-score play

    # Human hazard rate (accounting for fatigue, 1 error per ~5,000 moves)
    lambda_human_expert = 1.0 / 5000.0 # 2.0e-4 deaths/move
    lambda_human_avg = 1.0 / 1200.0   # 8.3e-4 deaths/move

    # Score range from 0 to 5 Million points (with extended curve up to 10M)
    scores = np.linspace(0, 5000000, 2000)
    moves = scores / points_per_move

    # Survival functions S(t) = exp(-lambda * moves)
    surv_optimal = np.exp(-lambda_optimal * moves) * 100.0
    surv_human_expert = np.exp(-lambda_human_expert * moves) * 100.0

    # Specific milestones to evaluate
    milestones = [
        (50000, "50k"),
        (100000, "100k"),
        (300000, "300k"),
        (500000, "500k"),
        (1000000, "1.0M"),
        (2000000, "2.0M"),
        (3000000, "3.0M"),
        (5000000, "5.0M")
    ]

    fig = plt.figure(figsize=(20, 14), dpi=160, facecolor='#0D1322')
    gs = fig.add_gridspec(2, 2, height_ratios=[1.2, 1.0], hspace=0.35, wspace=0.25)

    # =========================================================================
    # TOP PANEL (Span Columns): SURVIVAL PROBABILITY DECAY CURVE (0 to 5M SCORE)
    # =========================================================================
    ax_main = fig.add_subplot(gs[0, :])
    ax_main.set_facecolor('#151F38')

    # Plot optimal survival curve
    ax_main.plot(scores / 1000.0, surv_optimal, color='#00E5FF', linewidth=3.2, 
                 label='Optimal AI Solver (3-Ply Lookahead | Zero Blunders)', zorder=5)
    
    # Fill area under optimal curve
    ax_main.fill_between(scores / 1000.0, surv_optimal, color='#00E5FF', alpha=0.12)

    # Plot Human Expert comparison
    ax_main.plot(scores[:400] / 1000.0, surv_human_expert[:400], color='#FF5252', linewidth=2.2, 
                 linestyle='--', label='Human Master Player (1 blunder / 5,000 moves)', zorder=4)

    # Pin milestone callouts
    callout_targets = [100000, 300000, 1000000, 2000000, 5000000]
    callout_colors = ['#69F0AE', '#00E676', '#FFD700', '#FF9100', '#FF3D00']

    for target_score, col in zip(callout_targets, callout_colors):
        m_moves = target_score / points_per_move
        p_surv = np.exp(-lambda_optimal * m_moves) * 100.0
        x_k = target_score / 1000.0

        # Draw vertical reference line
        ax_main.axvline(x_k, color=col, linestyle=':', linewidth=1.2, alpha=0.6)

        # Marker point
        ax_main.scatter([x_k], [p_surv], color=col, s=120, zorder=10, edgecolor='#FFFFFF', linewidth=1.5)

        # Text annotation box
        offset_y = 6 if p_surv < 90 else -12
        if target_score == 100000:
            txt = f"100k Score\n{p_surv:.1f}% Odds\n(1 in 83 dies)"
            xytext = (-20, -50)
        elif target_score == 300000:
            txt = f"300k Score\n{p_surv:.1f}% Odds\n(1 in 28 dies)"
            xytext = (15, -45)
        elif target_score == 1000000:
            txt = f"1.0M SCORE\n{p_surv:.1f}% Odds\n(1 in 9 dies)\n~22.2 hrs play"
            xytext = (20, -35)
        elif target_score == 2000000:
            txt = f"2.0M Score\n{p_surv:.1f}% Odds\n(1 in 5 dies)"
            xytext = (25, -25)
        else:
            txt = f"5.0M Score\n{p_surv:.1f}% Odds\n(1 in 2 dies - Median Lifespan)"
            xytext = (20, 25)

        ax_main.annotate(txt, xy=(x_k, p_surv), xytext=xytext, textcoords="offset points",
                         ha='left', va='center', fontsize=9.5, fontweight='bold', color=col,
                         bbox=dict(boxstyle='round,pad=0.5', facecolor='#0D1322', edgecolor=col, alpha=0.9),
                         arrowprops=dict(arrowstyle="->", color=col, lw=1.2))

    ax_main.set_title("SURVIVAL PROBABILITY CURVE: PROBABILITY OF REACHING ULTRA-HIGH SCORES\n"
                      r"Model: $S(\text{score}) = \exp(-\lambda \cdot \frac{\text{score}}{12.5})$ with Empirical $\lambda = 1.5008 \times 10^{-6}$",
                      fontsize=15, fontweight='bold', color='#FFFFFF', pad=15)
    ax_main.set_xlabel("Score Milestone (Thousands of Points)", fontsize=12, fontweight='bold', color='#8EA8D8', labelpad=10)
    ax_main.set_ylabel("Probability of Unassisted Survival (%)", fontsize=11, fontweight='bold', color='#00E5FF')
    ax_main.set_xlim(-50, 5050)
    ax_main.set_ylim(-5, 110)
    ax_main.grid(True, linestyle=':', color='#2A3D66', alpha=0.5)
    ax_main.tick_params(colors='#EAF6FF')
    ax_main.legend(loc='lower left', frameon=True, facecolor='#151F38', edgecolor='#38509A', fontsize=10)

    # =========================================================================
    # BOTTOM LEFT PANEL: CUMULATIVE MORTALITY ODDS (1-in-N GAMES DIE)
    # =========================================================================
    ax_odds = fig.add_subplot(gs[1, 0])
    ax_odds.set_facecolor('#151F38')

    table_scores = [10000, 50000, 100000, 300000, 500000, 1000000, 2000000, 5000000]
    table_labels = ['10k', '50k', '100k', '300k', '500k', '1.0M', '2.0M', '5.0M']
    
    p_deaths = []
    one_in_n = []
    
    for s_val in table_scores:
        m_val = s_val / points_per_move
        p_d = 1.0 - np.exp(-lambda_optimal * m_val)
        p_deaths.append(p_d * 100.0)
        one_in_n.append(1.0 / p_d if p_d > 0 else 999999)

    x_bar = np.arange(len(table_scores))
    bars = ax_odds.bar(x_bar, p_deaths, color='#FF5252', edgecolor='#FF8A80', alpha=0.85, width=0.55)

    for i, (bar, d_pct, n_val) in enumerate(zip(bars, p_deaths, one_in_n)):
        h = bar.get_height()
        ax_odds.annotate(f"{d_pct:.1f}%\n(1 in {int(round(n_val))})", xy=(bar.get_x() + bar.get_width()/2, h),
                         xytext=(0, 4), textcoords="offset points", ha='center', va='bottom',
                         color='#FFFFFF', fontsize=8.5, fontweight='bold')

    ax_odds.set_title("B. Cumulative Failure Probability by Score Milestone", fontsize=13, fontweight='bold', color='#FFFFFF', pad=12)
    ax_odds.set_xlabel("Target Score Milestone", fontsize=11, fontweight='bold', color='#8EA8D8')
    ax_odds.set_ylabel("Probability of Forced Loss (%)", fontsize=11, fontweight='bold', color='#FF5252')
    ax_odds.set_xticks(x_bar)
    ax_odds.set_xticklabels(table_labels, fontweight='bold')
    ax_odds.set_ylim(0, max(p_deaths) * 1.25)
    ax_odds.grid(True, linestyle=':', color='#2A3D66', alpha=0.5, axis='y')
    ax_odds.tick_params(colors='#EAF6FF')

    # =========================================================================
    # BOTTOM RIGHT PANEL: PHYSICAL TIME & HUMAN BLUNDER COMPARISON
    # =========================================================================
    ax_time = fig.add_subplot(gs[1, 1])
    ax_time.set_facecolor('#151F38')
    ax_time.axis('off')

    # Text summary card
    summary_card = (
        "MATHEMATICAL ODDS & TIME SUMMARY\n"
        "────────────────────────────────────────────────────────────\n\n"
        "1. ODDS OF REACHING 300,000 SCORE:\n"
        "   • Optimal AI Solver:   96.5% chance (1 in 28 games dies)\n"
        "   • Human Master:         0.8% chance (without revives)\n"
        "   • Required Placements: ~24,000 moves (~6.7 continuous hours)\n\n"
        "2. ODDS OF REACHING 1,000,000 (1M) SCORE:\n"
        "   • Optimal AI Solver:   88.7% chance (1 in 9 games dies)\n"
        "   • Human Master:        0.0000000008% (virtually 0 without revives)\n"
        "   • Required Placements: ~80,000 moves (~22.2 continuous hours)\n\n"
        "3. MEDIAN LIFESPAN (50% GAME OVER POINT):\n"
        "   • Median Survival Step: 461,850 moves\n"
        "   • Median Score:        ~5,773,000 points\n"
        "   • Continuous Play Time: ~128.3 hours (~5.3 days non-stop)\n\n"
        "4. WHY THE CHANCES DECAY:\n"
        "   Because failure probability per step λ > 0 is non-zero,\n"
        "   the cumulative survival follows Poisson decay:\n"
        "               P(Survive T steps) = exp(-λ · T)\n"
        "   The longer you play, the probability of an unavoidable\n"
        "   POOL_HARD geometric trap strictly approaches 1.0 (100%)."
    )

    ax_time.text(0.04, 0.95, summary_card, transform=ax_time.transAxes, fontsize=10.5,
                 family='monospace', color='#00FFCC', va='top',
                 bbox=dict(boxstyle='round,pad=1.0', facecolor='#0D1322', edgecolor='#38509A', linewidth=1.5))

    plt.suptitle("BLOCK BLAST SURVIVAL MATHEMATICS: 300k, 1M & LONG-TERM ATTRITION", fontsize=16, fontweight='bold', color='#00E5FF', y=0.98)

    artifact_path = "/Users/jonathanarndt/.gemini/antigravity-cli/brain/834cc8bd-088d-4873-9d40-a0bb662f6a4f/survival_probability_curve.png"
    plt.savefig(artifact_path, bbox_inches='tight', dpi=160, facecolor='#0D1322')
    plt.savefig(out_png, bbox_inches='tight', dpi=160, facecolor='#0D1322')
    print(f"Survival probability chart saved to:\n  - {artifact_path}\n  - {out_png}")

if __name__ == '__main__':
    generate_survival_chart()
