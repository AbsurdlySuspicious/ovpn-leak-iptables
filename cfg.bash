ep_server=1.1.1.1
ep_network=10.8.0.0/24
ep_gateway=10.8.0.1
ep_device=tun0
ep_strict=1
ep_strict_icmp=0
ep_strict_udp=1120,1125
ep_strict_tcp=1145
ep_commit

ep_server=8.8.8.8
ep_network=10.8.1.0/24
ep_gateway=10.8.1.1
ep_device=tun1
ep_strict=1
ep_strict_udp=4000
ep_commit

ep_server=8.8.4.4
ep_network=10.8.2.0/24
ep_device=tun+
ep_commit

CHAIN=ovpn_leak
FINAL_RULE=DROP
INSERT_TO=A

