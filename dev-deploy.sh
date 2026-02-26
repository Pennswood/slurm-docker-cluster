#!/bin/bash
set -e

USAGE="Usage: $0 [--app APP_NAME] [--all] [--infra] [--restart]

Deploy OnDemand from source into the running container.

Options:
  --app APP_NAME   Deploy a single app (e.g. dashboard, myjobs, shell)
  --all            Build and deploy all apps + infrastructure
  --infra          Deploy infrastructure only (nginx_stage, ood-portal-generator, etc.)
  --restart        Kill all PUNs so changes take effect (automatic with --all)
  -h, --help       Show this help message

Examples:
  $0 --all                    # Full build + deploy
  $0 --app dashboard          # Deploy just the dashboard app
  $0 --app dashboard --restart # Deploy dashboard and restart PUNs
"

SRC_DIR=/opt/ood/src
SYS_APPS=/var/www/ood/apps/sys
OOD_INFRA=/opt/ood
APP_NAME=""
DEPLOY_ALL=false
DEPLOY_INFRA=false
RESTART_PUNS=false

export SECRET_KEY_BASE=${SECRET_KEY_BASE:-ooddevkeyfb5a43d9e7c8b1a0d2f364e5c7a9b81d0e2f4a6c8d0b3e5f7a9c1d3e5f7a9b1c}
export PASSENGER_APP_ENV=${PASSENGER_APP_ENV:-production}
export BUNDLE_BUILD__NOKOGIRI="--use-system-libraries"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --app) APP_NAME="$2"; shift 2 ;;
        --all) DEPLOY_ALL=true; RESTART_PUNS=true; shift ;;
        --infra) DEPLOY_INFRA=true; shift ;;
        --restart) RESTART_PUNS=true; shift ;;
        -h|--help) echo "$USAGE"; exit 0 ;;
        *) echo "Unknown option: $1"; echo "$USAGE"; exit 1 ;;
    esac
done

if [[ -z "$APP_NAME" && "$DEPLOY_ALL" == "false" && "$DEPLOY_INFRA" == "false" ]]; then
    echo "$USAGE"
    exit 1
fi

if [[ ! -d "$SRC_DIR" ]]; then
    echo "Error: Source directory $SRC_DIR not found."
    echo "Make sure the ondemand submodule is mounted in docker-compose.yml"
    exit 1
fi

cd "$SRC_DIR"

deploy_app() {
    local app=$1
    local src="$SRC_DIR/apps/$app"
    local dest="$SYS_APPS/$app"

    if [[ ! -d "$src" ]]; then
        echo "Error: App '$app' not found at $src"
        echo "Available apps: $(ls apps/)"
        exit 1
    fi

    echo "==> Building $app ..."
    if [[ -f "$src/bin/setup" ]]; then
        cd "$src"
        if [[ -f "Gemfile.lock" ]]; then
            bundle config set --local path vendor/bundle
            bundle config set --local build.nokogiri --use-system-libraries
            bundle install --jobs 4 --retry 2 2>&1
        fi
        if [[ -f "bin/setup" && -x "bin/setup" ]]; then
            bin/setup 2>&1
        fi
        cd "$SRC_DIR"
    fi

    echo "==> Deploying $app -> $dest ..."
    rsync -a --delete "$src/" "$dest/"
    chown -R root:root "$dest"
    echo "    Done: $app deployed."
}

deploy_infrastructure() {
    echo "==> Deploying infrastructure ..."
    for component in mod_ood_proxy nginx_stage ood_auth_map ood-portal-generator; do
        if [[ -d "$SRC_DIR/$component" ]]; then
            echo "    $component -> $OOD_INFRA/$component"
            rsync -a --delete "$SRC_DIR/$component/" "$OOD_INFRA/$component/"
        fi
    done
    echo "    Done: infrastructure deployed."
}

restart_puns() {
    echo "==> Restarting all PUNs ..."
    /opt/ood/nginx_stage/sbin/nginx_stage nginx_clean -f 2>/dev/null || true
    echo "    PUNs cleared. They will restart on next page load."
}

if [[ "$DEPLOY_ALL" == "true" ]]; then
    echo "==> Running full build ..."
    bundle config set --local path vendor/bundle
    bundle config set --local build.nokogiri --use-system-libraries
    bundle install --jobs 4 --retry 2 2>&1
    PASSENGER_APP_ENV=production rake build 2>&1

    for app_dir in apps/*/; do
        app=$(basename "$app_dir")
        echo "==> Deploying $app -> $SYS_APPS/$app ..."
        rsync -a --delete "$app_dir" "$SYS_APPS/$app/"
        chown -R root:root "$SYS_APPS/$app"
    done

    deploy_infrastructure
elif [[ -n "$APP_NAME" ]]; then
    deploy_app "$APP_NAME"
elif [[ "$DEPLOY_INFRA" == "true" ]]; then
    deploy_infrastructure
fi

if [[ "$RESTART_PUNS" == "true" ]]; then
    restart_puns
fi

echo ""
echo "Deploy complete. Visit http://localhost:8080"
