#!/usr/bin/env python3
"""Wertet Benchmark-CSVs aus und erzeugt Tabelle und Abbildung fuer das Paper.

    python3 analyze.py results/*.csv

Schreibt:
    results/summary.csv            Median und IQR je Server und Datei
    results/summary.md             Markdown-Tabelle fuer paper.md
    ../paper/figures/energy_per_1k.png
    ../paper/figures/throughput.png

Benoetigt nur die Standardbibliothek plus matplotlib fuer die Abbildungen.
Ohne matplotlib werden nur die Tabellen geschrieben.
"""
import csv
import statistics
import sys
from collections import defaultdict
from pathlib import Path

HERE = Path(__file__).resolve().parent
FIGDIR = HERE.parent / "paper" / "figures"
METRICS = ["rps", "latency_p99_s", "rss_load_bytes", "j_per_1k_req"]
LABELS = {
    "rps": "Requests/s",
    "latency_p99_s": "Latency p99 (s)",
    "rss_load_bytes": "RSS under load (MiB)",
    "j_per_1k_req": "J per 1000 requests",
}


def load(paths):
    rows = []
    for p in paths:
        with open(p, newline="", encoding="utf-8") as f:
            rows.extend(csv.DictReader(f))
    return rows


def num(v):
    try:
        return float(v)
    except (TypeError, ValueError):
        return None


def summarise(rows):
    groups = defaultdict(lambda: defaultdict(list))
    meta = {}
    for r in rows:
        key = (r["server"], r["file"])
        meta[key] = (r["image"], int(r["image_bytes"]), int(r["file_bytes"]), r["rss_idle_bytes"])
        for m in METRICS:
            v = num(r.get(m))
            if v is not None:
                groups[key][m].append(v)
    out = []
    for key in sorted(groups):
        server, file = key
        image, image_bytes, file_bytes, rss_idle = meta[key]
        rec = {"server": server, "image": image, "image_mib": round(image_bytes / 2**20, 1),
               "file": file, "file_bytes": file_bytes, "rss_idle_mib": round(num(rss_idle) / 2**20, 1) if num(rss_idle) else ""}
        for m in METRICS:
            vals = groups[key][m]
            if m == "rss_load_bytes":
                vals = [v / 2**20 for v in vals]
            if vals:
                q = statistics.quantiles(vals, n=4) if len(vals) >= 2 else [vals[0]] * 3
                rec[m + "_median"] = round(statistics.median(vals), 4)
                rec[m + "_iqr"] = round(q[2] - q[0], 4)
                rec[m + "_n"] = len(vals)
            else:
                rec[m + "_median"] = rec[m + "_iqr"] = ""
                rec[m + "_n"] = 0
        out.append(rec)
    return out


def write_csv(summary, path):
    with open(path, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=list(summary[0].keys()))
        w.writeheader()
        w.writerows(summary)


def write_md(summary, path):
    small = [s for s in summary if s["file"] == "index.html"]
    lines = ["| Image | Size (MiB) | RSS idle (MiB) | Requests/s (1 KiB) | p99 (ms) | J per 1000 req (1 KiB) |",
             "|---|---|---|---|---|---|"]
    for s in small:
        p99 = s["latency_p99_s_median"]
        p99 = f"{p99 * 1000:.1f}" if p99 != "" else "n/a"
        j = s["j_per_1k_req_median"]
        j = f"{j:.3f} ± {s['j_per_1k_req_iqr']:.3f}" if j != "" else "n/a"
        lines.append(f"| {s['image']} | {s['image_mib']} | {s['rss_idle_mib']} | {s['rps_median']:.0f} | {p99} | {j} |")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def plot(summary):
    try:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
    except ImportError:
        print("matplotlib fehlt, keine Abbildungen", file=sys.stderr)
        return
    FIGDIR.mkdir(parents=True, exist_ok=True)
    servers = sorted({s["server"] for s in summary})
    files = sorted({s["file"] for s in summary}, key=lambda f: next(s["file_bytes"] for s in summary if s["file"] == f))
    for metric, fname in (("j_per_1k_req", "energy_per_1k.png"), ("rps", "throughput.png")):
        fig, ax = plt.subplots(figsize=(7, 3.5))
        width = 0.8 / len(servers)
        for i, server in enumerate(servers):
            vals, errs = [], []
            for f in files:
                rec = next((s for s in summary if s["server"] == server and s["file"] == f), None)
                v = rec[metric + "_median"] if rec and rec[metric + "_median"] != "" else 0
                e = rec[metric + "_iqr"] if rec and rec[metric + "_iqr"] != "" else 0
                vals.append(v)
                errs.append(e)
            xs = [j + i * width for j in range(len(files))]
            ax.bar(xs, vals, width, yerr=errs, label=server, capsize=2)
        ax.set_xticks([j + width * (len(servers) - 1) / 2 for j in range(len(files))])
        ax.set_xticklabels(files)
        ax.set_ylabel(LABELS[metric])
        ax.legend(frameon=False, ncol=len(servers), fontsize=8)
        ax.spines[["top", "right"]].set_visible(False)
        fig.tight_layout()
        fig.savefig(FIGDIR / fname, dpi=200)
        plt.close(fig)
        print("geschrieben:", FIGDIR / fname)


def main(argv):
    paths = argv[1:] or sorted((HERE / "results").glob("*.csv"))
    paths = [p for p in paths if not str(p).endswith("summary.csv")]
    if not paths:
        sys.exit("keine Ergebnis-CSVs gefunden (results/*.csv)")
    rows = load(paths)
    if not rows:
        sys.exit("CSV-Dateien sind leer")
    summary = summarise(rows)
    write_csv(summary, HERE / "results" / "summary.csv")
    write_md(summary, HERE / "results" / "summary.md")
    print((HERE / "results" / "summary.md").read_text(encoding="utf-8"))
    plot(summary)


if __name__ == "__main__":
    main(sys.argv)
