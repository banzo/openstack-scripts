#!/bin/bash -e
# Creates some instances for networking-sfc demo/development:
# a web server, another instance to use as client
# three "service VMs" with two interface that will just route the packets to/from each interface

. $(dirname "${BASH_SOURCE}")/custom.sh
. $(dirname "${BASH_SOURCE}")/tools.sh

# Disable port security (else packets would be rejected when exiting the service VMs)
neutron net-update --port_security_enabled=False private

# Create network ports for all VMs
#for port in p1in p1out p2in p2out p3in p3out source_vm_port dest_vm_port
#do
#    neutron port-create --name "${port}" private
#done

neutron port-create private --fixed-ip ip_address=10.0.0.11 --name "p1in"
neutron port-create private --fixed-ip ip_address=10.0.0.12 --name "p1out"
neutron port-create private --fixed-ip ip_address=10.0.0.21 --name "p2in"
neutron port-create private --fixed-ip ip_address=10.0.0.22 --name "p2out"
neutron port-create private --fixed-ip ip_address=10.0.0.31 --name "p3in"
neutron port-create private --fixed-ip ip_address=10.0.0.32 --name "p3out"
neutron port-create private --fixed-ip ip_address=10.0.0.101 --name "source_vm_port"
neutron port-create private --fixed-ip ip_address=10.0.0.102 --name "dest_vm_port"



# SFC VMs
nova boot --image "${IMAGE}" --flavor "${FLAVOR}" \
    --key-name "${SSH_KEYNAME}" --security-groups "${SECGROUP}" \
    --nic port-id="$(neutron port-show -f value -c id p1in)" \
    --nic port-id="$(neutron port-show -f value -c id p1out)" \
    sfc-dpi
nova boot --image "${IMAGE}" --flavor "${FLAVOR}" \
    --key-name "${SSH_KEYNAME}" --security-groups "${SECGROUP}" \
    --nic port-id="$(neutron port-show -f value -c id p2in)" \
    --nic port-id="$(neutron port-show -f value -c id p2out)" \
    sfc-firewall
nova boot --image "${IMAGE}" --flavor "${FLAVOR}" \
    --key-name "${SSH_KEYNAME}" --security-groups "${SECGROUP}" \
    --nic port-id="$(neutron port-show -f value -c id p3in)" \
    --nic port-id="$(neutron port-show -f value -c id p3out)" \
    sfc-firewall-noftp

# Demo VMs
nova boot --image "${IMAGE}" --flavor "${FLAVOR}" \
    --key-name "${SSH_KEYNAME}" --security-groups "${SECGROUP}" \
    --nic port-id="$(neutron port-show -f value -c id source_vm_port)" \
    bsa_proxy
nova boot --image "${IMAGE}" --flavor "${FLAVOR}" \
    --key-name "${SSH_KEYNAME}" --security-groups "${SECGROUP}" \
    --nic port-id="$(neutron port-show -f value -c id dest_vm_port)" \
    dest_vm

# HTTP Flow classifier (catch the web traffic from source_vm to dest_vm)
SOURCE_IP=$(openstack port show source_vm_port -f value -c fixed_ips|grep "ip_address='[0-9]*\."|cut -d"'" -f2)
DEST_IP=$(openstack port show dest_vm_port -f value -c fixed_ips|grep "ip_address='[0-9]*\."|cut -d"'" -f2)
neutron flow-classifier-create \
    --ethertype IPv4 \
    --source-ip-prefix ${SOURCE_IP}/32 \
    --destination-ip-prefix ${DEST_IP}/32 \
    --protocol tcp \
    --destination-port 80:80 \
    --logical-source-port source_vm_port \
    FC_http

# UDP flow classifier (catch all UDP traffic from source_vm to dest_vm, like traceroute)
neutron flow-classifier-create \
    --ethertype IPv4 \
    --source-ip-prefix ${SOURCE_IP}/32 \
    --destination-ip-prefix ${DEST_IP}/32 \
    --protocol udp \
    --logical-source-port source_vm_port \
    FC_udp

# Get easy access to the VMs
route_to_subnetpool

# Create the port pairs for all 3 VMs
neutron port-pair-create --ingress=p1in --egress=p1out PP1
neutron port-pair-create --ingress=p2in --egress=p2out PP2
neutron port-pair-create --ingress=p3in --egress=p3out PP3

# And the port pair groups
neutron port-pair-group-create --port-pair PP1 --port-pair PP2 PG1
neutron port-pair-group-create --port-pair PP3 PG2

# The complete chain
neutron port-chain-create --port-pair-group PG1 --port-pair-group PG2 --flow-classifier FC_udp --flow-classifier FC_http PC1

sleep 5

# Start a basic demo web server
ssh -o StrictHostKeyChecking=no cirros@${DEST_IP} 'while true; do echo -e "HTTP/1.0 200 OK\r\n\r\nWelcome to $(hostname)" | sudo nc -l -p 80 ; done&'

# On service VMs, enable eth1 interface and add static routing
for sfc_port in p1in p2in p3in
do
    ssh -o StrictHostKeyChecking=no -T cirros@$(openstack port show ${sfc_port} -f value -c fixed_ips|grep "ip_address='[0-9]*\."|cut -d"'" -f2) <<EOF
sudo sh -c 'echo "auto eth1" >> /etc/network/interfaces'
sudo sh -c 'echo "iface eth1 inet dhcp" >> /etc/network/interfaces'
sudo /etc/init.d/S40network restart
sudo sh -c 'echo 1 > /proc/sys/net/ipv4/ip_forward'
sudo ip route add ${SOURCE_IP} dev eth0
sudo ip route add ${DEST_IP} dev eth1

EOF
done

# create captures
## T3
SKYDIVE_USERNAME=admin SKYDIVE_PASSWORD=pass123456 /opt/stack/go/bin/skydive --conf /tmp/skydive.yaml client capture create --name SFCFirewall11 --gremlin "G.V().Has('Neutron/IPs', Regex('10.0.0.11,*'))"
SKYDIVE_USERNAME=admin SKYDIVE_PASSWORD=pass123456 /opt/stack/go/bin/skydive --conf /tmp/skydive.yaml client capture create --name SFCFirewall12 --gremlin "G.V().Has('Neutron/IPs', Regex('10.0.0.12,*'))"

SKYDIVE_USERNAME=admin SKYDIVE_PASSWORD=pass123456 /opt/stack/go/bin/skydive --conf /tmp/skydive.yaml client capture create --name SFCDPI21 --gremlin "G.V().Has('Neutron/IPs', Regex('10.0.0.21,*'))"
SKYDIVE_USERNAME=admin SKYDIVE_PASSWORD=pass123456 /opt/stack/go/bin/skydive --conf /tmp/skydive.yaml client capture create --name SFCDPI22 --gremlin "G.V().Has('Neutron/IPs', Regex('10.0.0.22,*'))"

SKYDIVE_USERNAME=admin SKYDIVE_PASSWORD=pass123456 /opt/stack/go/bin/skydive --conf /tmp/skydive.yaml client capture create --name SFCFirewall31 --gremlin "G.V().Has('Neutron/IPs', Regex('10.0.0.31,*'))"
SKYDIVE_USERNAME=admin SKYDIVE_PASSWORD=pass123456 /opt/stack/go/bin/skydive --conf /tmp/skydive.yaml client capture create --name SFCFirewall32 --gremlin "G.V().Has('Neutron/IPs', Regex('10.0.0.32,*'))"

## T4
SKYDIVE_USERNAME=admin SKYDIVE_PASSWORD=pass123456 /opt/stack/go/bin/skydive --conf /tmp/skydive.yaml client capture create --name SFCFirewallt411 --gremlin "G.V().Has('Neutron/IPs', Regex('11.0.0.11,*'))"
SKYDIVE_USERNAME=admin SKYDIVE_PASSWORD=pass123456 /opt/stack/go/bin/skydive --conf /tmp/skydive.yaml client capture create --name SFCFirewallt412 --gremlin "G.V().Has('Neutron/IPs', Regex('11.0.0.12,*'))"

SKYDIVE_USERNAME=admin SKYDIVE_PASSWORD=pass123456 /opt/stack/go/bin/skydive --conf /tmp/skydive.yaml client capture create --name SFCDPIt421 --gremlin "G.V().Has('Neutron/IPs', Regex('11.0.0.21,*'))"
SKYDIVE_USERNAME=admin SKYDIVE_PASSWORD=pass123456 /opt/stack/go/bin/skydive --conf /tmp/skydive.yaml client capture create --name SFCDPIt422 --gremlin "G.V().Has('Neutron/IPs', Regex('11.0.0.22,*'))"

SKYDIVE_USERNAME=admin SKYDIVE_PASSWORD=pass123456 /opt/stack/go/bin/skydive --conf /tmp/skydive.yaml client capture create --name SFCFirewallt431 --gremlin "G.V().Has('Neutron/IPs', Regex('11.0.0.31,*'))"
SKYDIVE_USERNAME=admin SKYDIVE_PASSWORD=pass123456 /opt/stack/go/bin/skydive --conf /tmp/skydive.yaml client capture create --name SFCFirewallt432 --gremlin "G.V().Has('Neutron/IPs', Regex('11.0.0.32,*'))"

