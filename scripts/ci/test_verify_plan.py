"""Offline checks for the deployment authorization boundaries."""

import unittest

from verify_plan import check_manifest, check_run


class PlanChecks(unittest.TestCase):
    def setUp(self):
        self.repo = "owner/private-lab"
        self.commit = "a" * 40
        self.run = {
            "id": 123, "run_attempt": 2, "event": "workflow_dispatch",
            "head_branch": "main", "head_sha": self.commit,
            "status": "completed", "conclusion": "success",
            "path": ".github/workflows/terraform-plan.yml",
            "repository": {"full_name": self.repo},
            "head_repository": {"full_name": self.repo},
        }
        self.manifest = {
            "repository": self.repo, "commit": self.commit,
            "run_id": "123", "run_attempt": "2", "terraform_version": "1.16.4",
            "plan_sha256": "plan-hash", "lockfile_sha256": "lock-hash", "exit_code": 2,
        }

    def test_reviewed_successful_run_is_accepted(self):
        check_run(self.run, self.repo, self.commit, "123", "2")

    def test_successful_push_plan_is_accepted(self):
        check_run(dict(self.run, event="push"), self.repo, self.commit, "123", "2")

    def test_failed_wrong_branch_commit_workflow_or_attempt_is_rejected(self):
        for key, value in {
            "conclusion": "failure", "head_branch": "feature",
            "head_sha": "b" * 40, "path": ".github/workflows/other.yml",
            "run_attempt": 3, "event": "pull_request", "status": "in_progress",
        }.items():
            with self.subTest(key=key), self.assertRaises(ValueError):
                check_run(dict(self.run, **{key: value}), self.repo, self.commit, "123", "2")

    def test_fork_is_rejected(self):
        run = dict(self.run, head_repository={"full_name": "other/fork"})
        with self.assertRaises(ValueError):
            check_run(run, self.repo, self.commit, "123", "2")

    def test_intact_plan_is_accepted(self):
        check_manifest(self.manifest, self.repo, self.commit, "123", "2", "plan-hash", "lock-hash")

    def test_changed_plan_or_provider_lockfile_is_rejected(self):
        for plan_hash, lock_hash in (("tampered", "lock-hash"), ("plan-hash", "changed")):
            with self.subTest(plan=plan_hash, lock=lock_hash), self.assertRaises(ValueError):
                check_manifest(self.manifest, self.repo, self.commit, "123", "2", plan_hash, lock_hash)

    def test_manifest_wrong_identity_runtime_or_failed_plan_is_rejected(self):
        for key, value in {
            "repository": "other/repo", "commit": "b" * 40, "run_id": "999",
            "run_attempt": "1", "terraform_version": "1.15.0", "exit_code": 1,
        }.items():
            with self.subTest(key=key), self.assertRaises(ValueError):
                check_manifest(dict(self.manifest, **{key: value}), self.repo,
                               self.commit, "123", "2", "plan-hash", "lock-hash")


if __name__ == "__main__":
    unittest.main()
