#!/bin/bash

# Generate the final values
envsubst < values.yml > generated-values.yml

echo "Final generated-values.yml result"
cat generated-values.yml
