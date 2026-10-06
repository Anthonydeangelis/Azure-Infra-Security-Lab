"""Verify the source run and saved-plan identity before manual deployment."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import urllib.request


def check_run(run, repository, commit, run_id, attempt):
    expected = {
        "id": int(run_id),
        "run_attempt": int(attempt),
        "event": "workflow_dispatch",
        "head_branch": "main",
        "head_sha": commit,
        "status": "completed",
        "conclusion": "success",
        "path": ".github/workflows/terraform-plan.yml",
    }
    for key, value in expected.items():
        if run.get(key) != value:
            raise ValueError(f"Plan run has unexpected {key}; create and review a fresh plan.")
    for key in ("repository", "head_repository"):
        if run.get(key, {}).get("full_name", "").lower() != repository.lower():
            raise ValueError("Plan must originate from this repository, not a fork.")


def check_manifest(manifest, repository, commit, run_id, attempt, plan_hash, lock_hash):
    expected = {
        "repository": repository,
        "commit": commit,
        "run_id": str(run_id),
        "run_attempt": str(attempt),
        "terraform_version": "1.16.4",
        "plan_sha256": plan_hash,
        "lockfile_sha256": lock_hash,
    }
    for key, value in expected.items():
        if manifest.get(key) != value:
            raise ValueError(f"Plan manifest has unexpected {key}; create and review a fresh plan.")
    if manifest.get("exit_code") not in (0, 2):
        raise ValueError("Plan did not finish successfully.")


def api(path):
    request = urllib.request.Request(
        f"{os.environ['GITHUB_API_URL']}{path}",
        headers={
            "Authorization": f"Bearer {os.environ['GH_TOKEN']}",
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
        },
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)


def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("stage", choices=("run", "artifact"))
    args = parser.parse_args()
    repository = os.environ["GITHUB_REPOSITORY"]
    commit = os.environ["GITHUB_SHA"]
    run_id = os.environ["PLAN_RUN_ID"]
    attempt = os.environ["PLAN_ATTEMPT"]
    if not all(re.fullmatch(r"[1-9][0-9]*", value) for value in (run_id, attempt)):
        raise ValueError("Plan run ID and attempt must be positive integers.")
    if os.environ["CONFIRM_APPLY"] != "APPLY":
        raise ValueError("Type APPLY only after reviewing the selected plan.")

    if args.stage == "run":
        run = api(f"/repos/{repository}/actions/runs/{run_id}")
        check_run(run, repository, commit, run_id, attempt)
        branch = api(f"/repos/{repository}/branches/main")
        if branch["commit"]["sha"] != commit:
            raise ValueError("Main has changed; create and review a plan for the latest commit.")
        name = f"terraform-plan-{run_id}-{attempt}"
        found = []
        page = 1
        while True:
            artifacts = api(f"/repos/{repository}/actions/runs/{run_id}/artifacts?per_page=100&page={page}")["artifacts"]
            found.extend(a for a in artifacts if a["name"] == name and not a["expired"])
            if len(artifacts) < 100:
                break
            page += 1
        if len(found) != 1:
            raise ValueError("A single unexpired plan artifact is required; create a fresh plan.")
        with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as output:
            output.write(f"artifact_id={found[0]['id']}\n")
        print("Successful main-branch plan run and unexpired artifact verified.")
    else:
        review = Path(os.environ["TASK_DIR"]) / "review"
        manifest = json.loads((review / "manifest.json").read_text())
        check_manifest(manifest, repository, commit, run_id, attempt,
                       sha256(review / "lab.tfplan"), sha256("Terraform/.terraform.lock.hcl"))
        print("Saved plan checksum, commit, runtime and provider lockfile verified.")


if __name__ == "__main__":
    main()
