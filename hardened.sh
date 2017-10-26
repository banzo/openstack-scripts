#!/bin/bash -e
# Creates some instances for networking-sfc demo/development:
# a web server, another instance to use as client
# three "service VMs" with two interface that will just route the packets to/from each interface

. $(dirname "${BASH_SOURCE}")/custom.sh
. $(dirname "${BASH_SOURCE}")/tools.sh

neutron port-create private --fixed-ip ip_address=10.0.0.31 --name "p3in"
neutron port-create private --fixed-ip ip_address=10.0.0.32 --name "p3out"

nova boot --image "${IMAGE}" --flavor "${FLAVOR}" \
    --key-name "${SSH_KEYNAME}" --security-groups "${SECGROUP}" \
    --nic port-id="$(neutron port-show -f value -c id p3in)" \
    --nic port-id="$(neutron port-show -f value -c id p3out)" \
    sfc-firewall-hardened-t3

nova delete sfc-firewall-t3

neutron port-create sfc-t4 --fixed-ip ip_address=11.0.0.31 --name "p3in_t4"
neutron port-create sfc-t4 --fixed-ip ip_address=11.0.0.32 --name "p3out_t4"

nova boot --image "${IMAGE}" --flavor "${FLAVOR}" \
    --key-name "${SSH_KEYNAME}" --security-groups "${SECGROUP}" \
    --nic port-id="$(neutron port-show -f value -c id p3in_t4)" \
    --nic port-id="$(neutron port-show -f value -c id p3out_t4)" \
    sfc-firewall-hardened-t4

nova delete sfc-firewall-t4


sleep 5


