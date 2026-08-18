# Self-hosted GitHub Actions Runner on Render

This repository contains a Render Blueprint (`render.yaml`) and Dockerfile that deploys an ephemeral, self-hosted GitHub Actions runner as a background worker on Render.

## How it works

- **Ephemeral lifecycle:** The runner registers to GitHub, accepts exactly one job, deregisters, then loops to accept the next job. This matches GitHub's guidance for autoscaled self-hosted runners and ensures a clean environment per job.
- **Rootless Podman:** Workflows can use `docker build`/`docker run` via Podman, which runs in rootless mode (no privileged container access needed). This is validated immediately after deploy.
- **Automatic re-registration:** The entrypoint mints a fresh GitHub registration token via the REST API before each cycle, avoiding token expiry issues.
- **Graceful shutdown:** SIGTERM handling lets in-flight jobs finish within `maxShutdownDelaySeconds` (default 300s) before the runner deregisters.

## Deployment

### 1. Update render.yaml

Edit `render.yaml` and set `GITHUB_REPO` to your target repository (`owner/repo`).

### 2. Deploy via Render Blueprint

Push this repo to GitHub and deploy via Render's Blueprint feature. The worker will build and start immediately.

### 3. Set GITHUB_PAT in the Render Dashboard

The `GITHUB_PAT` environment variable is marked `sync: false` in the Blueprint, meaning it does not sync from the repo. Set it manually in the Render Dashboard:

1. Go to Render Dashboard → your worker service → Environment
2. Add `GITHUB_PAT` with a classic GitHub PAT (repo scope, at minimum `actions:write` on the target repo)
3. The worker will pick up the change and begin registering

## Validating rootless containers

Immediately after deploy, validate that Podman can run containers in Render's sandbox:

1. Go to Render Dashboard → your worker service → Shell
2. Run these commands:

```bash
# Confirm newuidmap/newgidmap have the setuid bit (required for user namespaces)
ls -l /usr/bin/newuidmap /usr/bin/newgidmap

# Confirm subuid/subgid ranges are configured
cat /etc/subuid /etc/subgid

# Smoke test: can Podman run a simple container?
podman run --rm hello-world

# Harder test: can Podman build and run a container?
echo -e 'FROM alpine\nRUN echo hi' | podman build -t smoke-test -f - .
podman run --rm smoke-test
```

If `newuidmap`/`newgidmap` lack the setuid bit (show `-rwxr-xr-x` instead of `-rwsr-xr-x`), or if `podman run` fails with `Operation not permitted` or a cgroup error, rootless containers are not available in Render's sandbox for this plan. You would then need to pursue an alternative approach for Docker-dependent workflows (out of scope for this plan).

## GitHub Actions Integration

Once deployed and validated, you can reference this runner in your target repo's workflows:

```yaml
name: Example Workflow
on: [push]

jobs:
  build:
    runs-on: self-hosted
    steps:
      - uses: actions/checkout@v4
      - run: echo "Running on self-hosted runner on Render"
      # Docker-based steps should work via Podman:
      - run: docker run --rm hello-world
```

The runner will appear in your repo's Settings → Actions → Runners as "Idle" until it picks up a job, "Active" during the job, and disappear after the job completes (ephemeral cleanup).

## Notes

- **Continuous billing:** The worker instance runs continuously, even while idle between jobs. It does not scale to zero.
- **Single concurrent job:** With `numInstances: 1` and one PAT, only one job runs at a time. Parallel or matrix jobs will queue in GitHub.
- **Broad PAT scope:** A classic PAT with `repo` scope is broad. Consider the security tradeoff for your use case. If the PAT has an expiry, set a calendar reminder to rotate it before expiry.
- **Plan sizing:** `standard` plan (2 vCPU, 4 GB RAM) is recommended as a starting point for `docker build` workloads; `starter` may be too small.

## Troubleshooting

- **Runner doesn't appear in GitHub Settings > Actions > Runners:** Check the worker logs in Render's Dashboard. The PAT may be invalid, the repo name may be wrong, or the GitHub API may be unreachable.
- **Jobs queue but don't start:** The runner may be stuck or crashed. Check the worker logs and the shell output from the validation tests above.
- **SIGTERM handling is broken:** Manually test by triggering a redeploy while a test job is running and observing whether it finishes gracefully or gets killed immediately.
