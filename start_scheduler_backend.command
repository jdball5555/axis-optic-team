#!/bin/zsh -l
# Axis CP-SAT Scheduler Backend Launcher
# Automatically sets up Python venv, installs requirements, and starts the FastAPI service.
cd "$(dirname "$0")/backend"
[ -f ~/.zshrc ] && source ~/.zshrc >/dev/null 2>&1
export PATH="$PATH:/opt/homebrew/bin:/usr/local/bin:$HOME/Library/Python/3.8/bin:$HOME/Library/Python/3.9/bin:$HOME/Library/Python/3.10/bin:$HOME/Library/Python/3.11/bin"

echo "========================================================"
echo " Starting Axis CP-SAT Scheduling Backend (Google OR-Tools)"
echo "========================================================"
echo

if ! command -v python3 >/dev/null 2>&1; then
  echo "Error: Python 3 is not installed or not in PATH."
  echo "Please install Python 3.10+ and re-run this script."
  read -r "?Press Return to close… "
  exit 1
fi

echo "Using Python: $(python3 --version)"

# Create virtual environment if it doesn't exist
if [ ! -d ".venv" ]; then
  echo "Creating virtual environment in backend/.venv..."
  python3 -m venv .venv
fi

# Activate venv
source .venv/bin/activate

echo "Checking & installing dependencies (FastAPI, OR-Tools, Pydantic)..."
pip install --quiet --upgrade pip
pip install -r requirements.txt

echo
echo "Starting FastAPI service on http://localhost:8000..."
echo "API Docs available at: http://localhost:8000/docs"
echo "Press Ctrl+C to stop the server."
echo "--------------------------------------------------------"

uvicorn main:app --host 0.0.0.0 --port 8000 --reload
