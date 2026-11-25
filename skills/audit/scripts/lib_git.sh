#!/usr/bin/env bash
# lib_git.sh: sourced by helpers that run git on the audited repository.
#
# The target's .git/config is attacker-controlled (a local path, a tarball, a
# vendored checkout). Command-line -c beats every config file, so each key that
# can spawn a process is pinned to an inert value here.

git_safe() {
  env -u GIT_EXTERNAL_DIFF -u GIT_SSH_COMMAND -u GIT_PAGER \
    GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_TERMINAL_PROMPT=0 GIT_OPTIONAL_LOCKS=0 \
    git --no-pager \
      -c core.fsmonitor=false \
      -c core.hooksPath=/dev/null \
      -c core.pager=cat \
      -c core.sshCommand=false \
      -c core.askPass=false \
      -c diff.external= \
      -c credential.helper= \
      -c protocol.allow=never \
      "$@"
}
