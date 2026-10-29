#!/usr/bin/env bash
# heks-linux
#
# SPDX-License-Identifier: MIT
# Copyright © Josep Bigorra <jjbigorra@gmail.com>
#
# github-repo.sh - reproduce a GitHub repository's settings from a JSON spec.
#
#   capture   read a reference repository and dump its settings to JSON
#   apply     create/configure a repository so it matches a spec (idempotent)
#   verify    diff a live repository against a spec
#
# The specification is plain JSON so it can be committed next to the code:
# a repository's whole GitHub configuration then lives in git, and any new
# repository is one command away from matching it.
#
# Requires: gh (authenticated), jq, git (only for --source/--push).
#
# Examples
#   scripts/github-repo.sh capture jjba23/nix-jointhefreeworld \
#       > scripts/github-repo-settings.json
#   scripts/github-repo.sh apply --repo jjba23/wolk-jjba --source . --push \
#       --description "wolk-jjba is my personal cloud, written as a Guile program"
#   scripts/github-repo.sh verify --repo jjba23/wolk-jjba

set -euo pipefail

readonly PROG=${0##*/}

# Resolve a directory to an absolute path.  CDPATH is emptied first: a
# non-empty CDPATH makes `cd` echo the target directory on stdout, which would
# silently poison the command substitution below.
resolve_dir() {
  local dir=$1
  (CDPATH='' cd -- "$dir" && pwd -P)
}

HERE=$(resolve_dir "$(dirname -- "${BASH_SOURCE[0]}")")
readonly HERE
readonly DEFAULT_SPEC="$HERE/github-repo-settings.json"

# Rules that newer/paid GitHub features add to a ruleset.  They are copied
# when the target repository supports them and dropped with a warning when
# it does not, so the same spec works for every repository.
readonly OPTIONAL_RULES=(copilot_code_review code_quality code_scanning)

DRY_RUN=0
PROTOCOL=''
SSH_HOST=''

log()  { printf '%s\n' "$*" >&2; }
step() { printf '\n== %s\n' "$*" >&2; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<EOF
Usage: $PROG <command> [options]

Commands
  capture OWNER/REPO [--out FILE]
      Print the repository's GitHub configuration as JSON.

  apply --repo OWNER/REPO [options]
      Create the repository if needed and make it match --spec.
      Options:
        --spec FILE          settings to apply (default: ./github-repo-settings.json)
        --source DIR         local git checkout to attach to the new repository
        --push               push the default branch (and tags) from --source
        --all-refs           also push every other local branch
        --no-tags            do not push tags with --push
        --remote NAME        git remote to create/update (default: origin)
        --protocol P         ssh | https for the new remote (default: gh config)
        --ssh-host HOST      ssh host alias for github (default: found in ~/.ssh/config)
        --description TEXT   repository description
        --visibility V       public | private | internal (default: from spec)
        --dry-run            print mutating calls instead of running them

  verify --repo OWNER/REPO [--spec FILE]
      Capture the live repository and diff it against the spec.

Notes
  * A git remote that points at codeberg.org is renamed to "codeberg" before
    the GitHub remote is added, so the old host stays around for a while.
  * Rules and features the target repository cannot use (Copilot code review,
    code quality, code scanning, extra-approval-for-unattributed-changes) are
    dropped with a warning instead of failing the run.
  * --dry-run still performs read-only API calls so it can report what exists.
EOF
}

# --- API helpers -----------------------------------------------------------

# query PATH [JQ_FILTER] - read-only, always executed (even with --dry-run)
query() { gh api "$1" --jq "${2:-.}"; }

# api METHOD PATH [JSON] - mutating call, gated by --dry-run
api() {
  local method=$1 path=$2 payload=${3-}
  if ((DRY_RUN)); then
    log "dry-run: gh api -X $method $path ${payload:+<<< $payload}"
    return 0
  fi
  if [[ -n $payload ]]; then
    gh api -X "$method" "$path" --input - >/dev/null <<<"$payload"
  else
    gh api -X "$method" "$path" >/dev/null
  fi
}

# api_collect METHOD PATH JSON - like api, but prints the response on stdout.
api_collect() {
  local method=$1 path=$2 payload=$3
  if ((DRY_RUN)); then
    log "dry-run: gh api -X $method $path" >&2
    return 0
  fi
  gh api -X "$method" "$path" --input - <<<"$payload"
}

# api_try METHOD PATH [JSON] - like api, but a rejection is only a warning.
# Used for features that depend on the plan/visibility of the repository
# (secret scanning on private repos, Copilot, code quality, ...).
api_try() {
  local method=$1 path=$2 payload=${3-} err
  if ((DRY_RUN)); then
    api "$method" "$path" "$payload"
    return 0
  fi
  if ! err=$(api "$method" "$path" "$payload" 2>&1); then
    warn "$method $path not applied: ${err:-unknown error}${payload:+ [sent: $payload]}"
  fi
}

run_git() {
  local dir=$1
  shift
  if ((DRY_RUN)); then
    log "dry-run: git -C $dir $*"
    return 0
  fi
  git -C "$dir" "$@"
}

repo_exists() { gh api "repos/$1" --silent >/dev/null 2>&1; }

require_tools() {
  local tool
  for tool in "$@"; do
    command -v "$tool" >/dev/null 2>&1 || die "$tool is required but not installed"
  done
  gh auth status >/dev/null 2>&1 || die "gh is not authenticated; run 'gh auth login'"
}

# --- capture ---------------------------------------------------------------

cmd_capture() {
  local tpl=${1-} out=''
  [[ -n $tpl ]] || die "capture needs OWNER/REPO"
  shift
  while (($#)); do
    case $1 in
      --out) out=$2; shift 2 ;;
      -h | --help) usage; exit 0 ;;
      *) die "unknown argument: $1" ;;
    esac
  done
  require_tools gh jq

  local tmp
  tmp=$(mktemp -d)

  step "capturing $tpl"
  gh api "repos/$tpl" >"$tmp/repo.json"
  gh api "repos/$tpl/private-vulnerability-reporting" >"$tmp/pvr.json" 2>/dev/null ||
    printf '{"enabled":false}\n' >"$tmp/pvr.json"
  gh api "repos/$tpl/actions/permissions" >"$tmp/actions.json" 2>/dev/null ||
    printf '{}\n' >"$tmp/actions.json"
  gh api "repos/$tpl/actions/permissions/workflow" >"$tmp/workflow.json" 2>/dev/null ||
    printf '{}\n' >"$tmp/workflow.json"

  local n=0 id
  for id in $(gh api "repos/$tpl/rulesets" --jq '.[].id' 2>/dev/null || true); do
    n=$((n + 1))
    gh api "repos/$tpl/rulesets/$id" |
      jq 'del(.id, .node_id, .source, .source_type, ._links,
              .created_at, .updated_at, .current_user_can_bypass)' \
        >"$tmp/ruleset-$n.json"
  done

  local rulesets='[]'
  if compgen -G "$tmp/ruleset-*.json" >/dev/null; then
    rulesets=$(jq -s 'sort_by(.name)' "$tmp"/ruleset-*.json)
  fi

  local json
  json=$(jq -n \
    --arg template "$tpl" \
    --arg captured_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --argjson rulesets "$rulesets" \
    --slurpfile repo "$tmp/repo.json" \
    --slurpfile pvr "$tmp/pvr.json" \
    --slurpfile actions "$tmp/actions.json" \
    --slurpfile workflow "$tmp/workflow.json" \
    '{
      template: $template,
      captured_at: $captured_at,
      repo: ($repo[0] | {
        default_branch,
        visibility,
        description: null,
        has_issues,
        has_projects,
        has_wiki,
        has_discussions,
        web_commit_signoff_required,
        is_template,
        allow_forking,
        allow_squash_merge,
        allow_merge_commit,
        allow_rebase_merge,
        delete_branch_on_merge,
        allow_auto_merge,
        allow_update_branch,
        squash_merge_commit_title,
        squash_merge_commit_message,
        merge_commit_title,
        merge_commit_message,
        security_and_analysis: ($repo[0].security_and_analysis // {})
      }),
      private_vulnerability_reporting: ($pvr[0].enabled // false),
      actions_permissions: ($actions[0] | {enabled, allowed_actions, sha_pinning_required}),
      workflow_permissions: ($workflow[0] | {default_workflow_permissions, can_approve_pull_request_reviews}),
      rulesets: $rulesets
    }')

  if [[ -n $out ]]; then
    printf '%s\n' "$json" >"$out"
    log "wrote $out"
  else
    printf '%s\n' "$json"
  fi
  rm -rf "$tmp"
}

# --- apply -----------------------------------------------------------------

# GitHub is often reached through an ssh alias (this machine uses
# `Host personal.github.com` with its own key), so prefer an alias from
# ~/.ssh/config that points at github.com.
detect_ssh_host() {
  local cfg=${HOME}/.ssh/config host
  [[ -r $cfg ]] || { printf 'github.com'; return; }
  host=$(awk '
    /^[[:space:]]*[Hh]ost[[:space:]]/ && NF >= 2 && $2 != "*" { host = $2 }
    /^[[:space:]]*[Hh]ost[Nn]ame[[:space:]]+github\.com[[:space:]]*$/ { print host; exit }
  ' "$cfg")
  printf '%s' "${host:-github.com}"
}

ssh_reaches_github() {
  local out
  out=$(ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new \
    -o ConnectTimeout=5 -T "git@$SSH_HOST" 2>&1 || true)
  [[ $out == *"successfully authenticated"* ]]
}

# A live agent socket, or nothing.
#
# The inherited SSH_AUTH_SOCK cannot be trusted: a terminal passes on the
# socket of the agent that was running when it started, and a shell (or an
# editor, or a script) that outlives that agent keeps pointing at a path that
# no longer exists.  ssh then never asks the real agent, so a
# passphrase-protected key looks "not registered" -- which is exactly the wrong
# diagnosis.  So: the inherited socket only counts while it answers, and
# otherwise the session's own answer (systemd user environment, then the usual
# runtime paths) is used.
resolve_ssh_agent() {
  local runtime=${XDG_RUNTIME_DIR:-/run/user/$(id -u)} candidate status
  local -a candidates=()
  [[ -n ${SSH_AUTH_SOCK-} ]] && candidates+=("$SSH_AUTH_SOCK")
  while IFS= read -r candidate; do
    [[ -n $candidate ]] && candidates+=("$candidate")
  done < <(systemctl --user show-environment 2>/dev/null |
             sed -n 's/^SSH_AUTH_SOCK=//p')
  candidates+=("$runtime/gcr/ssh"
               "$runtime/ssh-agent/socket"
               "$runtime/ssh-agent.socket")

  for candidate in "${candidates[@]}"; do
    [[ -S $candidate ]] || continue
    # 0 = identities listed, 1 = a live agent with none, 2 = cannot connect.
    status=0
    SSH_AUTH_SOCK=$candidate ssh-add -l >/dev/null 2>&1 || status=$?
    if ((status <= 1)); then
      printf '%s' "$candidate"
      return 0
    fi
  done
  return 1
}

github_url() {
  local slug=$1 proto=$PROTOCOL
  [[ -n $proto ]] || proto=$(gh config get git_protocol --host github.com 2>/dev/null || true)
  [[ -n $proto ]] || proto=https
  case $proto in
    ssh) printf 'git@%s:%s.git' "${SSH_HOST:-github.com}" "$slug" ;;
    *) printf 'https://github.com/%s.git' "$slug" ;;
  esac
}

# For https pushes, let gh supply the token as a credential, repo-locally.
use_gh_credentials() {
  local dir=$1
  run_git "$dir" config --local credential.'https://github.com'.helper '!gh auth git-credential'
}

ensure_remote() {
  local dir=$1 name=$2 slug=$3 url current agent idfile
  url=$(github_url "$slug")

  case $url in
    https://*) use_gh_credentials "$dir" ;;
    *)
      if agent=$(resolve_ssh_agent); then
        if [[ $agent != "${SSH_AUTH_SOCK-}" ]]; then
          [[ -n ${SSH_AUTH_SOCK-} ]] &&
            log "ignoring a dead SSH_AUTH_SOCK ($SSH_AUTH_SOCK)"
          log "using the agent at $agent"
          # Exported so the push below, and anything else this script runs,
          # finds the same agent.
          export SSH_AUTH_SOCK=$agent
        fi
      elif [[ -n ${SSH_AUTH_SOCK-} && ! -S $SSH_AUTH_SOCK ]]; then
        warn "SSH_AUTH_SOCK points at $SSH_AUTH_SOCK, which is not a socket"
      fi

      if ! ssh_reaches_github; then
        idfile=$(ssh -G "$SSH_HOST" 2>/dev/null | awk '/^identityfile /{print $2; exit}')
        local hint="  Add ${idfile:-your key} to https://github.com/settings/keys, or re-run with --protocol https."
        if [[ -z ${SSH_AUTH_SOCK-} ]]; then
          hint="  No ssh agent is reachable: unlock the key once (ssh-add ${idfile:-<key>}), or re-run with --protocol https."
        fi
        if ((DRY_RUN)); then
          warn "ssh to $SSH_HOST does not authenticate; a real run would stop here.
$hint"
        else
          die "ssh to $SSH_HOST does not authenticate.
$hint"
        fi
      fi
      ;;
  esac

  if current=$(git -C "$dir" remote get-url "$name" 2>/dev/null); then
    case $current in
      *github.com[:/]"$slug".git)
        if [[ $current == "$url" ]]; then
          log "remote $name -> $current"
        else
          log "updating remote $name: $current -> $url"
          run_git "$dir" remote set-url "$name" "$url"
        fi
        return 0
        ;;
    esac
    if [[ $current == *codeberg.org* ]] && ! git -C "$dir" remote get-url codeberg >/dev/null 2>&1; then
      log "renaming remote $name -> codeberg ($current)"
      run_git "$dir" remote rename "$name" codeberg
    else
      die "remote $name points at $current, not $url; rename or remove it first"
    fi
  fi
  log "adding remote $name -> $url"
  run_git "$dir" remote add "$name" "$url"
}

# Drop one unsupported thing from a ruleset payload.  Prints the reduced
# payload, or fails when nothing is left to drop.
reduce_ruleset_payload() {
  local payload=$1 rule
  if jq -e '.rules[]
            | select(.type == "pull_request")
            | .parameters.require_extra_approval_for_unattributed_changes == true' \
      >/dev/null 2>&1 <<<"$payload"; then
    warn "dropping unsupported pull_request parameter: require_extra_approval_for_unattributed_changes"
    jq -c '.rules |= map(if .type == "pull_request"
                         then .parameters |= del(.require_extra_approval_for_unattributed_changes)
                         else . end)' <<<"$payload"
    return 0
  fi
  for rule in "${OPTIONAL_RULES[@]}"; do
    if jq -e --arg rule "$rule" '.rules | any(.type == $rule)' >/dev/null 2>&1 <<<"$payload"; then
      warn "dropping unsupported rule: $rule"
      jq -c --arg rule "$rule" '.rules |= map(select(.type != $rule))' <<<"$payload"
      return 0
    fi
  done
  return 1
}

apply_ruleset() {
  local slug=$1 name=$2 payload=$3 id=''
  step "ruleset: $name"
  if repo_exists "$slug"; then
    # --jq prints API errors on stdout, so keep only a numeric id
    id=$(gh api "repos/$slug/rulesets" \
      --jq ".[]? | select(.name == \"$name\") | .id" 2>/dev/null || true)
    [[ $id =~ ^[0-9]+$ ]] || id=''
  fi

  if ((DRY_RUN)); then
    if [[ -n $id ]]; then
      log "dry-run: gh api -X PUT repos/$slug/rulesets/$id <<< $payload"
    else
      log "dry-run: gh api -X POST repos/$slug/rulesets <<< $payload"
    fi
    return 0
  fi

  local attempt=$payload response
  while :; do
    if [[ -n $id ]]; then
      if response=$(gh api -X PUT "repos/$slug/rulesets/$id" --input - 2>&1 <<<"$attempt"); then
        log "updated ruleset $name (id $id)"
        return 0
      fi
    elif response=$(gh api -X POST "repos/$slug/rulesets" --input - 2>&1 <<<"$attempt"); then
      id=$(jq -r '.id' <<<"$response")
      log "created ruleset $name (id $id)"
      return 0
    fi
    case $response in
      *"Upgrade to GitHub Pro"*)
        # Rulesets are not available on free private repositories; no amount of
        # payload trimming will change that.
        warn "rulesets need a public repository or a paid plan; skipping '$name'"
        return 0
        ;;
    esac
    attempt=$(reduce_ruleset_payload "$attempt") ||
      die "could not apply ruleset '$name': $response"
  done
}

cmd_apply() {
  local spec=$DEFAULT_SPEC slug='' src='' desc='' visibility='' remote='origin'
  local push=0 tags=1 allrefs=0
  while (($#)); do
    case $1 in
      --spec) spec=$2; shift 2 ;;
      --repo) slug=$2; shift 2 ;;
      --source) src=$2; shift 2 ;;
      --push) push=1; shift ;;
      --all-refs) allrefs=1; shift ;;
      --no-tags) tags=0; shift ;;
      --remote) remote=$2; shift 2 ;;
      --protocol) PROTOCOL=$2; shift 2 ;;
      --ssh-host) SSH_HOST=$2; shift 2 ;;
      --description) desc=$2; shift 2 ;;
      --visibility) visibility=$2; shift 2 ;;
      --dry-run) DRY_RUN=1; shift ;;
      -h | --help) usage; exit 0 ;;
      *) die "unknown argument: $1" ;;
    esac
  done

  [[ -f $spec ]] || die "spec not found: $spec"
  jq -e . "$spec" >/dev/null || die "spec is not valid JSON: $spec"
  require_tools gh jq
  [[ -n $slug ]] || die "apply needs --repo OWNER/REPO"
  [[ $slug == */* ]] || slug="$(query user '.login')/$slug"
  [[ -n $visibility ]] || visibility=$(jq -r '.repo.visibility // "public"' "$spec")
  local owner=${slug%%/*} owner_type
  owner_type=$(gh api "users/$owner" --jq '.type' 2>/dev/null || true)
  [[ -n $owner_type ]] || owner_type=User
  if ((push)); then
    [[ -n $src ]] || src=$(pwd -P)
    git -C "$src" rev-parse --git-dir >/dev/null 2>&1 ||
      die "--push needs a git checkout (--source DIR)"
  fi
  [[ -n $SSH_HOST ]] || SSH_HOST=$(detect_ssh_host)
  if ((DRY_RUN)); then
    log "dry-run: no changes will be made"
  fi

  # 1. the repository itself
  step "repository $slug"
  if repo_exists "$slug"; then
    log "already exists"
  else
    local visflag="--$visibility"
    if ((DRY_RUN)); then
      log "dry-run: gh repo create $slug $visflag ${desc:+--description $desc}"
    else
      gh repo create "$slug" "$visflag" ${desc:+--description "$desc"} >/dev/null
      log "created ($visibility)"
    fi
  fi

  # 2. git remote + initial push (so the default branch exists before patching)
  if [[ -n $src ]]; then
    step "git remote in $src"
    ensure_remote "$src" "$remote" "$slug"
    if ((push)); then
      local branch def
      branch=$(git -C "$src" symbolic-ref --quiet --short HEAD) ||
        die "cannot push from a detached HEAD"
      def=$(jq -r '.repo.default_branch // empty' "$spec")
      def=${def:-$branch}
      [[ $branch == "$def" ]] ||
        die "checked out on '$branch' but the spec protects '$def'; check '$def' out first"
      step "pushing $branch"
      run_git "$src" push -u "$remote" "$branch"
      if ((tags)); then
        run_git "$src" push "$remote" --tags
      fi
      if ((allrefs)); then
        run_git "$src" push "$remote" --all
      fi
    fi
  fi

  # 3. general and merge settings
  # 3. general and merge settings.  Applied in dependency order and mostly one
  #    field per call, because GitHub rejects some fields on their own terms:
  #    allow_forking is org-only for private repos, the squash/merge message
  #    pairs must be sent together, merge messages need their strategy enabled,
  #    and the default branch can only be set once it exists.
  step "repository settings"
  local key value

  if [[ -n $desc ]]; then
    api_try PATCH "repos/$slug" "$(jq -cn --arg d "$desc" '{description: $d}')"
    log "description: $desc"
  fi

  value=$(jq -r '.repo.visibility // empty' "$spec")
  value=${visibility:-$value}
  if [[ -n $value ]]; then
    api_try PATCH "repos/$slug" "{\"visibility\":\"$value\"}"
    log "visibility: $value"
  fi

  for key in has_issues has_projects has_wiki has_discussions \
    web_commit_signoff_required is_template allow_forking allow_auto_merge \
    allow_update_branch delete_branch_on_merge; do
    value=$(jq -r --arg k "$key" '.repo[$k] | if . == null then empty else tostring end' "$spec")
    [[ -n $value ]] || continue
    if [[ $key == allow_forking && $owner_type != Organization ]]; then
      # GitHub only lets organisations change this on private repositories.
      log "allow_forking: managed by GitHub for user-owned repositories, skipping"
      continue
    fi
    api_try PATCH "repos/$slug" "{\"$key\":$value}"
  done

  for key in allow_merge_commit allow_squash_merge allow_rebase_merge; do
    value=$(jq -r --arg k "$key" '.repo[$k] | if . == null then empty else tostring end' "$spec")
    [[ -n $value ]] || continue
    api_try PATCH "repos/$slug" "{\"$key\":$value}"
  done

  local title message
  title=$(jq -r '.repo.squash_merge_commit_title // empty' "$spec")
  message=$(jq -r '.repo.squash_merge_commit_message // empty' "$spec")
  if [[ -n $title && -n $message ]]; then
    api_try PATCH "repos/$slug" \
      "{\"squash_merge_commit_title\":\"$title\",\"squash_merge_commit_message\":\"$message\"}"
  fi

  # Merge messages are only meaningful while merge commits are allowed.
  if [[ $(jq -r '.repo.allow_merge_commit // false' "$spec") == true ]]; then
    title=$(jq -r '.repo.merge_commit_title // empty' "$spec")
    message=$(jq -r '.repo.merge_commit_message // empty' "$spec")
    if [[ -n $title && -n $message ]]; then
      api_try PATCH "repos/$slug" \
        "{\"merge_commit_title\":\"$title\",\"merge_commit_message\":\"$message\"}"
    fi
  fi

  local branch
  branch=$(jq -r '.repo.default_branch // empty' "$spec")
  if [[ -n $branch ]]; then
    if gh api "repos/$slug/branches/$branch" --silent >/dev/null 2>&1; then
      api PATCH "repos/$slug" "{\"default_branch\":\"$branch\"}"
      log "default branch: $branch"
    elif ((DRY_RUN)); then
      log "dry-run: gh api -X PATCH repos/$slug <<< {\"default_branch\":\"$branch\"}"
    else
      warn "default branch '$branch' does not exist yet; push it and re-run apply"
    fi
  fi

  # 4. security features, one call per feature so a paid-only one cannot
  #    block the others
  step "security"
  local feature status
  for feature in secret_scanning secret_scanning_push_protection \
    secret_scanning_non_provider_patterns secret_scanning_validity_checks; do
    status=$(jq -r --arg f "$feature" '.repo.security_and_analysis[$f].status // empty' "$spec")
    [[ -n $status ]] || continue
    api_try PATCH "repos/$slug" "{\"security_and_analysis\":{\"$feature\":{\"status\":\"$status\"}}}"
    log "$feature: $status"
  done

  local dependabot
  dependabot=$(jq -r '.repo.security_and_analysis.dependabot_security_updates.status // empty' "$spec")
  if [[ $dependabot == enabled ]]; then
    api_try PUT "repos/$slug/automated-security-fixes" '{}'
    log "dependabot security updates: enabled"
  elif [[ $dependabot == disabled ]]; then
    api_try DELETE "repos/$slug/automated-security-fixes"
    log "dependabot security updates: disabled"
  fi

  if jq -e '.private_vulnerability_reporting == true' "$spec" >/dev/null; then
    api_try PUT "repos/$slug/private-vulnerability-reporting" '{}'
    log "private vulnerability reporting: enabled"
  else
    api_try DELETE "repos/$slug/private-vulnerability-reporting"
    log "private vulnerability reporting: disabled"
  fi

  # 5. Actions permissions
  step "actions"
  local actions workflow
  actions=$(jq -c '.actions_permissions | with_entries(select(.value != null))' "$spec")
  if [[ $actions != '{}' ]]; then
    api_try PUT "repos/$slug/actions/permissions" "$actions"
    log "repository actions permissions applied"
  fi
  workflow=$(jq -c '.workflow_permissions | with_entries(select(.value != null))' "$spec")
  if [[ $workflow != '{}' ]]; then
    api_try PUT "repos/$slug/actions/permissions/workflow" "$workflow"
    log "default workflow permissions applied"
  fi

  # 6. branch rulesets (modern replacement for branch protection)
  local count i name payload
  count=$(jq '.rulesets | length' "$spec")
  for ((i = 0; i < count; i++)); do
    name=$(jq -r ".rulesets[$i].name" "$spec")
    payload=$(jq -c ".rulesets[$i]" "$spec")
    apply_ruleset "$slug" "$name" "$payload"
  done

  step "done"
  log "https://github.com/$slug"
}

# --- verify ----------------------------------------------------------------

normalize_spec() {
  jq -S '
    del(.template, .captured_at)
    | .repo.description = null
    | .rulesets |= (map(.rules |= sort_by(.type)) | sort_by(.name))
  ' "$1"
}

cmd_verify() {
  local spec=$DEFAULT_SPEC slug=''
  while (($#)); do
    case $1 in
      --spec) spec=$2; shift 2 ;;
      --repo) slug=$2; shift 2 ;;
      -h | --help) usage; exit 0 ;;
      *) die "unknown argument: $1" ;;
    esac
  done
  [[ -f $spec ]] || die "spec not found: $spec"
  [[ -n $slug ]] || die "verify needs --repo OWNER/REPO"
  require_tools gh jq

  local tmp
  tmp=$(mktemp -d)

  cmd_capture "$slug" --out "$tmp/live.json"
  normalize_spec "$spec" >"$tmp/want.json"
  normalize_spec "$tmp/live.json" >"$tmp/have.json"

  local status=0
  if diff -u "$tmp/want.json" "$tmp/have.json" >"$tmp/diff.json"; then
    log "$slug matches $spec"
  else
    log "$slug differs from $spec:"
    cat "$tmp/diff.json" >&2
    status=1
  fi
  rm -rf "$tmp"
  return "$status"
}

# --- entry point -----------------------------------------------------------

main() {
  (($#)) || { usage; exit 1; }
  local command=$1
  shift
  case $command in
    capture) cmd_capture "$@" ;;
    apply) cmd_apply "$@" ;;
    verify) cmd_verify "$@" ;;
    -h | --help | help) usage ;;
    *) die "unknown command: $command (try --help)" ;;
  esac
}

main "$@"
