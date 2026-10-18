#!/usr/bin/env bash
# Zapisuje logi w osobnej gałęzi (np. ci-android), żeby można je było przejrzeć przez git fetch.
branch=$1; shift
mkdir -p /tmp/ci-logs
for f in "$@"; do [ -f "$f" ] && cp "$f" /tmp/ci-logs/; done
echo "run ${GITHUB_RUN_NUMBER} ${GITHUB_SHA} $(date -u +%FT%TZ) job=${GITHUB_JOB}" > /tmp/ci-logs/run.txt
cd /tmp/ci-logs || exit 0
git init -q && git checkout -q -b "$branch"
git config user.name "github-actions"; git config user.email "github-actions@users.noreply.github.com"
git add -A && git commit -qm "logi ${GITHUB_RUN_NUMBER}"
git push -qf "https://x-access-token:${TOKEN}@github.com/${GITHUB_REPOSITORY}.git" "$branch" || true
