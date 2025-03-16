RUNAS="sudo -iu $USER"

$RUNAS bash<<_
set -e
echo "Removing the self-hosted runner..."

if [ -f ".env" ]; then
    echo "Sourcing .env file..."
    set -a
    source .env
    set +a
    cd actions-runner
    # Remove the runner
    ./svc.sh stop
    ./svc.sh uninstall
    ./config.sh remove --unattended --token "${GITHUB_RUNNER_TOKEN}"
    echo "actions-runner removed successfully!"  
else
    echo ".env file not found, no need to uninstall..."
fi
_