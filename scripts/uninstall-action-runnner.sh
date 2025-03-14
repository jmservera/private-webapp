RUNAS="sudo -iu $USER"

$RUNAS bash<<_
set -e
echo "Removing the self-hosted runner..."
if [ -d "actions-runner" ]; then
    cd actions-runner
    # Remove the runner
    ./svc.sh stop
    ./svc.sh uninstall
    ./config.sh remove --unattended --token "${GITHUB_REPO_TOKEN}"
    echo "actions-runner removed successfully!"
else
    echo "actions-runner not found, nothing to remove."
    exit 0
fi
_