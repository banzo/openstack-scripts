#!/bin/bash -e
# Creates some instances for networking-sfc demo/development:
# a web server, another instance to use as client
# three "service VMs" with two interface that will just route the packets to/from each interface

. $(dirname "${BASH_SOURCE}")/custom.sh
. $(dirname "${BASH_SOURCE}")/tools.sh

# Disable port security (else packets would be rejected when exiting the service VMs)
neutron net-update --port_security_enabled=False private

neutron port-create private --fixed-ip ip_address=10.0.0.11 --name "p1in"
neutron port-create private --fixed-ip ip_address=10.0.0.12 --name "p1out"
neutron port-create private --fixed-ip ip_address=10.0.0.21 --name "p2in"
neutron port-create private --fixed-ip ip_address=10.0.0.22 --name "p2out"
neutron port-create private --fixed-ip ip_address=10.0.0.101 --name "source_vm_port"


# SFC VMs
nova boot --image "${IMAGE}" --flavor "${FLAVOR}" \
    --key-name "${SSH_KEYNAME}" --security-groups "${SECGROUP}" \
    --nic port-id="$(neutron port-show -f value -c id p1in)" \
    --nic port-id="$(neutron port-show -f value -c id p1out)" \
    sfc-dpi-t3
nova boot --image "${IMAGE}" --flavor "${FLAVOR}" \
    --key-name "${SSH_KEYNAME}" --security-groups "${SECGROUP}" \
    --nic port-id="$(neutron port-show -f value -c id p2in)" \
    --nic port-id="$(neutron port-show -f value -c id p2out)" \
    sfc-firewall-t3

# Demo VMs
nova boot --image "${IMAGE}" --flavor "${FLAVOR}" \
    --key-name "${SSH_KEYNAME}" --security-groups "${SECGROUP}" \
    --nic port-id="$(neutron port-show -f value -c id source_vm_port)" \
    bsa_proxy-t3


sleep 5


# DO THE T4 SFC SETUP

neutron net-create sfc-t4
neutron subnet-create --name sfc-t4-sn --ip-version 4 sfc-t4 11.0.0.0/24
neutron router-interface-add router1 sfc-t4-sn

# Disable port security (else packets would be rejected when exiting the service VMs)
neutron net-update --port_security_enabled=False sfc-t4

neutron port-create sfc-t4 --fixed-ip ip_address=11.0.0.11 --name "p1in_t4"
neutron port-create sfc-t4 --fixed-ip ip_address=11.0.0.12 --name "p1out_t4"
neutron port-create sfc-t4 --fixed-ip ip_address=11.0.0.21 --name "p2in_t4"
neutron port-create sfc-t4 --fixed-ip ip_address=11.0.0.22 --name "p2out_t4"
neutron port-create sfc-t4 --fixed-ip ip_address=11.0.0.101 --name "source_vm_port_t4"

# SFC VMs
nova boot --image "${IMAGE}" --flavor "${FLAVOR}" \
    --key-name "${SSH_KEYNAME}" --security-groups "${SECGROUP}" \
    --nic port-id="$(neutron port-show -f value -c id p1in_t4)" \
    --nic port-id="$(neutron port-show -f value -c id p1out_t4)" \
    sfc-dpi-t4
nova boot --image "${IMAGE}" --flavor "${FLAVOR}" \
    --key-name "${SSH_KEYNAME}" --security-groups "${SECGROUP}" \
    --nic port-id="$(neutron port-show -f value -c id p2in_t4)" \
    --nic port-id="$(neutron port-show -f value -c id p2out_t4)" \
    sfc-firewall-t4

# Demo VMs
nova boot --image "${IMAGE}" --flavor "${FLAVOR}" \
    --key-name "${SSH_KEYNAME}" --security-groups "${SECGROUP}" \
    --nic port-id="$(neutron port-show -f value -c id source_vm_port_t4)" \
    bsa_proxy-t4

SKYDIVE_USERNAME=admin SKYDIVE_PASSWORD=pass123456 /opt/stack/go/bin/skydive --conf /tmp/skydive.yaml client capture create --gremlin "G.V().Has('Name', 'br-int', 'Type', 'ovsbridge')"
SKYDIVE_USERNAME=admin SKYDIVE_PASSWORD=pass123456 /opt/stack/go/bin/skydive --conf /tmp/skydive.yaml client capture create --gremlin "G.V().Has('Name', Regex('^tap.*'))"
SKYDIVE_USERNAME=admin SKYDIVE_PASSWORD=pass123456 /opt/stack/go/bin/skydive --conf /tmp/skydive.yaml client capture create  --name SFCport80 --gremlin "G.Flows().Has('Transport','80').Nodes()"
