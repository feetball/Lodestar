# How to run work in this repo

## Models and roles

- The main session coordinates. It does not need to do the reading itself on big jobs.
- `haiku-runner` (Haiku 5.5): simple, mechanical work only: run one command, grep scans, list or count files.
- Sonnet 5.5 subagents (the general-purpose agent with `model: sonnet`): anything that has to read code and reason about it.
- `opus-advisor` (Opus 5.5): called once per job, after the parallel work is merged, to verify the findings against `origin/main` and rank them. Do not call it for small tasks.

## When to fan out

Only fan out for large jobs (a repo-wide review or audit, or a change that touches many independent areas). Do small tasks directly in the main session. For a large job, split the work into independent slices and launch the agents in parallel in one message.

## Do not guess

Every claim about the code needs a file and line and a concrete trace of how it fails. If it cannot be traced, label it "unverified" and say what would settle it. Check the code on `origin/main`, not a stale local branch, before reporting that a bug exists. There is no Swift toolchain here, so CI is the compiler; say so when a claim could only be settled by building or running.

## Review agents

Review agents are read-only: they do not edit, commit or push. Fixes are made by the main session, one pull request per concern, branched from `origin/main`.
