#!/bin/bash

declare SYNC_BUCKET="/npc" \
    SYNC_BUCKET_ACCESS="https://npc.nos-eastchina1.126.net"

log(){
    echo "[ $(date -R) ] $*" >&2
}

sync_repo() {
    local REPO="$1"
    echo "Syncing repo $REPO..."
    mkdir -p "target/$REPO"
    curl -fsSL "$SYNC_BUCKET_ACCESS/$REPO/index.yaml" >"target/$REPO/index.yaml" || {
        log "failed to fetch $SYNC_BUCKET_ACCESS/$REPO/index.yaml"
        exit 1
    }
    for CHART in "$REPO"/*; do
        log "building $CHART..."
        helm dependency build "$CHART" || helm dependency update "$CHART" || {
            log "failed to build $CHART" 
            return 1
        } 
        mkdir -p "target/$CHART" && \
        helm package --destination "target/$REPO" "$CHART" || {
            log "failed to package $CHART" 
            return 1    
        }
    done
    log "indexing $REPO..."
    helm repo index --url "$SYNC_BUCKET_ACCESS/$REPO" --merge "target/$REPO/index.yaml" "target/$REPO" || {
        log "failed to index $REPO"
        return 1
    }
    for CHART in "target/$REPO"/*.tgz; do
        log "uploading $CHART..."
        npc nos PUT "$SYNC_BUCKET/$REPO/${CHART##*/}" "@$CHART" || {
            log "failed to upload $CHART"
            return 1
        }
    done
    npc nos PUT "$SYNC_BUCKET/$REPO/index.yaml" "@target/$REPO/index.yaml" || {
        log "failed to upload index.yaml"
        return 1
    }
    return 0
}

# npc nos PUT "/npc/charts/stable/index.yaml" $'apiVersion: v1\nentries: {}'
# npc nos PUT "/npc/charts/incubator/index.yaml" $'apiVersion: v1\nentries: {}'
SCRIPT="${BASH_SOURCE[0]}" && [ -L "$SCRIPT" ] && SCRIPT="$(readlink -f "$SCRIPT")"
cd "$(dirname $SCRIPT)" || exit 1

log "fetching charts submodule..."
git submodule foreach git clean -fd && \
git submodule foreach git pull origin master || {
    log "failed to pull submodule"
    exit 1
}

export HELM_HOME=$PWD/target/.home && mkdir -p "$HELM_HOME" && \
helm init --client-only || exit 1

#helm init --client-only --stable-repo-url "$SYNC_BUCKET_ACCESS/charts/stable" || exit 1
# helm repo add "stable-origin" "https://kubernetes-charts.storage.googleapis.com" || {
#    log "failed to add repo stable-origin, ignoring"
#}
helm serve & HELM_PID="$!" && trap "kill $HELM_PID" EXIT
for REPO in charts/{stable,incubator}; do
    # helm repo add "$(basename "$REPO")" "$SYNC_BUCKET_ACCESS/$REPO" && \
    sync_repo $REPO || break
done
