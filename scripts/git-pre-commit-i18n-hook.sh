#!/bin/bash
# Optional git pre-commit hook that rejects a commit if the staged
# translations.dart has any key with < 33 locales.
#
# To activate:
#   ln -s ../../scripts/git-pre-commit-i18n-hook.sh .git/hooks/pre-commit
#
# See CLAUDE.md Arbeitsregel #7 and Cleona_Chat_Architecture_v2_2.md §13.

set -e

# Only run if translations.dart is in the set of staged changes; unrelated
# commits pass through untouched.
if ! git diff --cached --name-only | grep -q '^lib/core/i18n/translations\.dart$'; then
  exit 0
fi

repo_root="$(git rev-parse --show-toplevel)"
if ! dart "$repo_root/scripts/check_i18n_complete.dart"; then
  echo ""
  echo "Pre-commit hook: i18n coverage check failed. Commit refused."
  echo "Fix the missing translations, then git commit again."
  exit 1
fi
