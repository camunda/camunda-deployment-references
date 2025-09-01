#!/bin/bash

export AZURE_LOCATION="swedencentral"
export RESOURCE_GROUP_NAME="camunda-tf-rg"
export AZURE_STORAGE_ACCOUNT_NAME="camundatfstate" # must be globally unique
export AZURE_STORAGE_CONTAINER_NAME="camundatfstate"
export AZURE_TF_KEY="camunda-terraform/terraform.tfstate"
