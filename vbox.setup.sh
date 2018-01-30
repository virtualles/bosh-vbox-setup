#!/usr/bin/env bash

set -eux

START_PATH=$(pwd)

# install Director VM
git clone https://github.com/cloudfoundry/bosh-deployment || true

mkdir -p deployments/vbox

pushd ./deployments/vbox

bosh create-env "${START_PATH}"/bosh-deployment/bosh.yml \
  --state ./state.json \
  -o "${START_PATH}"/bosh-deployment/virtualbox/cpi.yml \
  -o "${START_PATH}"/bosh-deployment/virtualbox/outbound-network.yml \
  -o "${START_PATH}"/bosh-deployment/bosh-lite.yml \
  -o "${START_PATH}"/bosh-deployment/bosh-lite-runc.yml \
  -o "${START_PATH}"/bosh-deployment/jumpbox-user.yml \
  --vars-store ./creds.yml \
  -v director_name="Bosh Lite Director" \
  -v internal_ip=192.168.50.6 \
  -v internal_gw=192.168.50.1 \
  -v internal_cidr=192.168.50.0/24 \
  -v outbound_network_name=NatNetwork

# alias and log into the Director
bosh alias-env vbox -e 192.168.50.6 --ca-cert <(bosh int ./creds.yml --path /director_ssl/ca)

ENVIRONMENT=vbox
CLIENT=admin
CLIENT_SECRET=$(bosh int ./creds.yml --path /admin_password)

pushd "${START_PATH}"

touch .envrc
direnv allow
{
  echo "export BOSH_ENVIRONMENT=$ENVIRONMENT"; \
  echo "export BOSH_CLIENT=$CLIENT"; \
  echo "export BOSH_CLIENT_SECRET=$CLIENT_SECRET"
} > .envrc
cat .envrc
direnv allow

# running bosh status
bosh -e $ENVIRONMENT env

# Optionally, set up a local route for bosh ssh command

# sudo route add -net 10.244.0.0/16    192.168.50.6 # Mac OS X
# sudo route add -net 10.244.0.0/16 gw 192.168.50.6 # Linux
# route add           10.244.0.0/16    192.168.50.6 # Windows

# update cloud config
yes | bosh -e $ENVIRONMENT update-cloud-config "${START_PATH}"/bosh-deployment/warden/cloud-config.yml

# upload stemcell
bosh -e $ENVIRONMENT upload-stemcell https://bosh.io/d/stemcells/bosh-warden-boshlite-ubuntu-trusty-go_agent?v=3468.17 \
  --sha1 1dad6d85d6e132810439daba7ca05694cec208ab

# deploy example deployment
yes | bosh -e $ENVIRONMENT -d zookeeper deploy <(wget -O- https://raw.githubusercontent.com/cppforlife/zookeeper-release/master/manifests/zookeeper.yml)

# verify deployment
bosh -e $ENVIRONMENT -d zookeeper dep

# run example smoke tests
bosh -e $ENVIRONMENT -d zookeeper run-errand smoke-tests
