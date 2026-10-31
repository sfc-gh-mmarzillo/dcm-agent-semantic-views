"""Run the Cortex Agent evaluation against DEV and fail if scores fall below a threshold.

Used by .github/workflows/pr.yml after every DEV deploy; also runnable locally:
    SNOWFLAKE_CONNECTION=default python ci/run_evals.py --run-name local_test

Steps: build a fresh dataset from EVAL_QUESTIONS -> upload the eval config to the
DCM-managed EVAL_STAGE -> EXECUTE_AI_EVALUATION START -> poll STATUS -> score gate.
"""
import argparse
import os
import re
import sys
import tempfile
import time

import snowflake.connector

DB, SCHEMA, AGENT = "DCM_DEMO", "SALES_AI_DEV", "SALES_AGENT"
STAGE = f"{DB}.{SCHEMA}.EVAL_STAGE"
CONFIG_TEMPLATE = os.path.join(os.path.dirname(__file__), "..", "evals", "sales_agent_eval.yaml")
TERMINAL = {"COMPLETED", "PARTIALLY_COMPLETED", "FAILED", "CANCELLED"}


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--run-name", required=True)
    p.add_argument("--threshold", type=float, default=float(os.getenv("EVAL_THRESHOLD", "0.75")))
    p.add_argument("--timeout-min", type=int, default=30)
    args = p.parse_args()
    run = re.sub(r"[^A-Za-z0-9_]", "_", args.run_name).upper()
    dataset = f"{DB}.{SCHEMA}.EVALSET_{run}"

    conn = snowflake.connector.connect(
        connection_name=os.getenv("SNOWFLAKE_CONNECTION", "default"),
        role=os.getenv("SNOWFLAKE_ROLE", "DCM_DEPLOYER"),
    )
    cur = conn.cursor()
    cur.execute(f"USE SCHEMA {DB}.{SCHEMA}")

    # 1. Dataset snapshot of the eval questions for this run
    cur.execute(
        "CALL SYSTEM$CREATE_EVALUATION_DATASET('Cortex Agent', %s, %s, "
        "OBJECT_CONSTRUCT('query_text', 'INPUT_QUERY', 'expected_tools', 'EXPECTED_OUTPUT'))",
        (f"{DB}.{SCHEMA}.EVAL_QUESTIONS", dataset),
    )
    print(cur.fetchone()[0])

    # 2. Per-run config pointing at that dataset
    with open(CONFIG_TEMPLATE) as f:
        cfg = re.sub(r"dataset_name: \S+", f"dataset_name: {dataset}", f.read())
    cfg_dir = tempfile.mkdtemp()
    cfg_file = os.path.join(cfg_dir, f"{run.lower()}.yaml")
    with open(cfg_file, "w") as f:
        f.write(cfg)
    cur.execute(f"PUT 'file://{cfg_file}' @{STAGE}/configs AUTO_COMPRESS=FALSE OVERWRITE=TRUE")
    cfg_path = f"@{STAGE}/configs/{os.path.basename(cfg_file)}"

    # 3. Start + poll
    cur.execute("CALL EXECUTE_AI_EVALUATION('START', OBJECT_CONSTRUCT('run_name', %s), %s)", (run, cfg_path))
    print(cur.fetchone()[0])
    deadline = time.time() + args.timeout_min * 60
    status = None
    while time.time() < deadline:
        cur.execute("CALL EXECUTE_AI_EVALUATION('STATUS', OBJECT_CONSTRUCT('run_name', %s), %s)", (run, cfg_path))
        row = dict(zip([c[0] for c in cur.description], cur.fetchone()))
        status = row["STATUS"]
        print(f"status={status}")
        if status in TERMINAL:
            break
        time.sleep(30)
    if status not in ("COMPLETED", "PARTIALLY_COMPLETED"):
        print(f"Evaluation did not complete: {status} {row.get('STATUS_DETAILS')}")
        return 1

    # 4. Scores (metric rows can land shortly after COMPLETED)
    sql = f"""
        SELECT record_attributes:"ai.observability.eval.metric_name"::string AS metric,
               COUNT(*) AS n,
               ROUND(AVG(record_attributes:"ai.observability.eval_root.score"::float), 3) AS avg_score
        FROM TABLE(SNOWFLAKE.LOCAL.GET_AI_OBSERVABILITY_EVENTS('{DB}', '{SCHEMA}', '{AGENT}', 'CORTEX AGENT'))
        WHERE record_attributes:"ai.observability.span_type"::string = 'eval_root'
          AND record_attributes:"snow.ai.observability.run.name"::string = %s
        GROUP BY metric ORDER BY metric"""
    scores = []
    for _ in range(10):
        cur.execute(sql, (run,))
        scores = cur.fetchall()
        if scores:
            break
        time.sleep(30)
    if not scores:
        print("No metric scores found for run.")
        return 1

    lines = [f"### Agent eval `{run}` (threshold {args.threshold})", "| metric | n | avg | result |", "|---|---|---|---|"]
    failed = False
    for metric, n, avg in scores:
        ok = avg is not None and avg >= args.threshold
        failed |= not ok
        lines.append(f"| {metric} | {n} | {avg} | {'PASS' if ok else 'FAIL'} |")
    report = "\n".join(lines)
    print(report)
    if os.getenv("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as f:
            f.write(report + "\n")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
