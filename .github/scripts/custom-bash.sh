#!/bin/bash
# custom-bash.sh
# Charge les fonctions, puis exécute le script temporaire passé via {0}

# shellcheck disable=SC1091
source "./gha-functions.sh"
/usr/bin/env bash "$@"
