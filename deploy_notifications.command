#!/bin/zsh -l
# Turns on push notifications for Axis Team: uploads the small server job
# (functions/index.js) that sends promotion notifications when they're due.
# Run it once now, and again only if functions/index.js changes.
# Needs: Node.js (https://nodejs.org) and the Firebase project on the Blaze plan.
cd "$(dirname "$0")"
[ -f ~/.zshrc ] && source ~/.zshrc >/dev/null 2>&1
export PATH="$PATH:/opt/homebrew/bin:/usr/local/bin:$HOME/.npm-global/bin"
exec > >(tee deploy_output.txt) 2>&1

finish() {
  echo
  echo "$1"
  echo "You can close this window."
  read -r "?Press Return to close… "
  exit 0
}

if ! command -v npm >/dev/null 2>&1; then
  finish "Node.js isn't installed. Install the LTS version from https://nodejs.org, then double-click this file again."
fi
echo "Node $(node --version)"

if command -v firebase >/dev/null 2>&1; then
  fb() { firebase "$@"; }
else
  fb() { npx --yes firebase-tools@latest "$@"; }
fi

echo
echo "Installing the server job's packages…"
(cd functions && npm install --no-fund --no-audit) || finish "Installing packages failed (see above)."

if ! fb login:list 2>/dev/null | grep -q "Logged in as"; then
  echo
  echo "Sign in to Firebase in the browser window that opens…"
  fb login || finish "Firebase sign-in didn't finish."
fi

echo
echo "Uploading to Firebase (project-attendance-app)… this takes a few minutes the first time."
fb deploy --only functions --project project-attendance-app --force
code=$?
echo "EXIT: $code"
if [ $code -eq 0 ]; then
  finish "Done! Promotion notifications are on."
else
  finish "The upload didn't finish. If it mentions the Blaze plan, upgrade the project at https://console.firebase.google.com/project/project-attendance-app/usage/details and run this again."
fi
