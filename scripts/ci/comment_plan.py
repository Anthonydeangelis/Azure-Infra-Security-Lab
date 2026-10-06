"""Post the post-merge Terraform plan to its associated merged pull request."""

import html
import json
import os
from pathlib import Path
import urllib.request


def api(path, body=None):
    request = urllib.request.Request(
        os.environ["GITHUB_API_URL"] + path,
        data=json.dumps(body).encode() if body is not None else None,
        headers={
            "Authorization": "Bearer " + os.environ["GH_TOKEN"],
            "Accept": "application/vnd.github+json",
            "Content-Type": "application/json",
            "X-GitHub-Api-Version": "2022-11-28",
        },
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)


def main():
    repo = os.environ["GITHUB_REPOSITORY"]
    commit = os.environ["GITHUB_SHA"]
    run = os.environ["GITHUB_RUN_ID"]
    attempt = os.environ["GITHUB_RUN_ATTEMPT"]
    pulls = api(f"/repos/{repo}/commits/{commit}/pulls?per_page=100")
    pulls = [pr for pr in pulls if pr.get("merged_at")
             and pr["base"]["ref"] == "main" and pr.get("merge_commit_sha") == commit]
    if not pulls:
        print("No merged pull request for this main commit; plan is available in the run summary.")
        return
    text = (Path(os.environ["TASK_DIR"]) / "review" / "plan.txt").read_text()
    # Bound the escaped text to stay below GitHub's comment limit.
    escaped = html.escape(text)
    truncated = len(escaped) > 45000
    body = (f"## Terraform plan after merge\n\nCommit: `{commit}`\n\n"
            f"[Plan run]({os.environ['GITHUB_SERVER_URL']}/{repo}/actions/runs/{run}) "
            f"· Run ID: `{run}` · Attempt: `{attempt}`\n\n"
            "<details><summary>View proposed changes</summary>\n\n<pre>"
            + escaped[:45000] + "</pre>\n</details>\n\n")
    if truncated:
        body += "Output truncated. Review the artifact's complete plan.txt before applying.\n\n"
    body += "No apply was performed. Deployment still requires the manual apply workflow."
    for pull in pulls:
        api(f"/repos/{repo}/issues/{pull['number']}/comments", {"body": body})
    print("Posted the plan to the merged pull request.")


if __name__ == "__main__":
    main()
