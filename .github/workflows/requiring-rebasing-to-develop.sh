#!/bin/bash

context='Requiring rebasing to develop'

success_status=$(cat <<- END
	{
		"state": "success",
		"context": "$context",
		"description": "You can merge this Pull Request."
	}
	END
)

failure_status=$(cat <<- END
	{
		"state": "failure",
		"context": "$context",
		"description": "You must rebase this feature branch to the latest develop branch."
	}
	END
)

if [[ $# -lt 3 ]] ; then
  echo 'The arguments is not enought.' > /dev/stderr
  exit 1
fi
repo=$1  # e.g. octocat/hello
current_branch=$2  # A current branch is needed to check on the PR opening (check below)
githubToken=$3
api="https://api.github.com/repos/$repo"

function main () {
  echo "Checking this branch: $current_branch"
  check "$current_branch"

  curl --silent \
    --header 'Accept: application/vnd.github.v3+json' \
    --header "Authorization: token $githubToken" \
    "$api/pulls" \
    | jq -r '.[].head.ref' \
    | while read -r branch
  do
    if [[ $branch = 'develop' ]] ; then
      continue
    fi
    echo "Checking this branch: $branch"
    check "$branch"
  done
}

function check () {
  local branch=$1

  if is_rebased_to_develop "$branch" ; then
    echo "This has rebased. This will be made to 'success'"
    update_status_to "$success_status" "$branch"
    echo 'Done.'
    echo
    return
  fi

  echo "This has not rebased. This status will be made to 'failure'"
  update_status_to "$failure_status" "$branch"
  echo 'Done.'
  echo
}

function is_rebased_to_develop () {
  if [[ $1 = '' ]] ; then
    echo 'Invalid' > /dev/stderr
    exit 1
  fi
  local branch=$1 ancestor develop_head

  ancestor=$(git merge-base origin/develop "origin/$branch" | head -n 1)
  develop_head=$(git rev-parse origin/develop)

  [[ $ancestor = "$develop_head" ]]
}

function update_status_to () {
  if [[ $1 = '' ]] ; then
    echo 'Invalid' > /dev/stderr
    exit 1
  fi
  local updater_status=$1
  local branch=$2
  local branch_ref_response branch_head_commit_sha

  branch_ref_response=$( \
    curl --silent \
      --header "Authorization: token $githubToken" \
      --header 'Accept: application/vnd.github.v3+json' \
      "$api/git/ref/heads/$(encode_url "$branch")" \
  )
  branch_head_commit_sha=$(echo "$branch_ref_response" | jq -r .object.sha)
  if [[ $branch_head_commit_sha = 'null' ]] ; then
    echo "An invalid branch 'ref' response returned!" > /dev/stderr
    echo "$branch_ref_response" > /dev/stderr
    exit 1
  fi

  statuses_response=$( \
    curl --silent \
      --request POST \
      --header "Authorization: token $githubToken" \
      --header "Accept: application/vnd.github.v3+json" \
      --data "$updater_status" \
      "$api/statuses/$branch_head_commit_sha"
  )
  statuses_context=$(echo "$statuses_response" | jq -r .context)
  if [[ $statuses_context != "$context" ]] ; then
    echo "An invalid 'statuses' response returned!" > /dev/stderr
    echo '- - - - -' > /dev/stderr
    echo "$statuses_response" > /dev/stderr
    echo '- - - - -' > /dev/stderr
    exit 1
  fi
}

function encode_url () {
  echo "$1"  | nkf -WwMQ | tr '=' %
}

main
