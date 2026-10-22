#!/bin/zsh -l
# Builds the Axis Team website and publishes it to team.axisoptic.com
# (Firebase Hosting site "project-attendance-app"). Log: deploy_team_output.txt
cd "$(dirname "$0")"
[ -f ~/.zshrc ] && source ~/.zshrc >/dev/null 2>&1
export PATH="$PATH:$HOME/development/flutter/bin:$HOME/flutter/bin:$HOME/dev/flutter/bin:/opt/homebrew/bin:/usr/local/bin:$HOME/.npm-global/bin"
exec > >(tee deploy_team_output.txt) 2>&1
if command -v firebase >/dev/null 2>&1; then fb() { firebase "$@"; }; else fb() { npx --yes firebase-tools@latest "$@"; }; fi
echo "Building the website…"
if ! flutter build web --release --no-tree-shake-icons; then
  echo "BUILD FAILED"
  echo "EXIT: 1"
  read -r "?Press Return to close… "
  exit 1
fi
# Give this build a unique version so browsers can't keep running an old copy.
V=$(date +%Y%m%d%H%M%S)
perl -pi -e "s/flutter_bootstrap\.js(\?v=[^\"]*)?\"/flutter_bootstrap.js?v=$V\"/" build/web/index.html
perl -pi -e "s/\"main\.dart\.js\"/\"main.dart.js?v=$V\"/g" build/web/flutter_bootstrap.js
echo "Build version: $V"
grep -o "flutter_bootstrap.js?v=[0-9]*" build/web/index.html
grep -o "main.dart.js?v=[0-9]*" build/web/flutter_bootstrap.js | head -1
echo
echo "Publishing to team.axisoptic.com…"
fb deploy --only hosting --project project-attendance-app
echo "EXIT: $?"
echo "Done. You can close this window."
read -r "?Press Return to close… "
