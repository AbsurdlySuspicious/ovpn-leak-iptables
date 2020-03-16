# Config help

<!-- vim-markdown-toc GFM -->

* [Specifying endpoints/servers](#specifying-endpointsservers)
  * [`ep_server`](#ep_server)
  * [`ep_network`](#ep_network)
  * [`ep_gateway`](#ep_gateway)
  * [`ep_device`](#ep_device)
  * [`ep_strict`](#ep_strict)
  * [`ep_strict_udp`, `ep_strict_tcp`](#ep_strict_udp-ep_strict_tcp)
  * [`ep_strict_icmp`](#ep_strict_icmp)
* [Miscellaneous](#miscellaneous)
  * [`WHITELIST`](#whitelist)
  * [`FINAL_RULE`](#final_rule)
  * [`INSERT_TO`](#insert_to)
  * [`CHAIN`](#chain)
  * [Embedded chains override](#embedded-chains-override)

<!-- vim-markdown-toc -->

## Specifying endpoints/servers

You can specify multiple endpoints.
After each enpoint configured, you should write `ep_commit`
as it done in [config example](config_example)

### `ep_server`

Required: **yes**

IP address of this endpoint/server. 
Note that your vpn client config ahould also point to IP address,
not a domain as dns resolving might not be available when vpn is
disconnected.

### `ep_network`

Required: **yes**

Network address of this endpoint/vpn. Should be specified with CIDR mask.

Examples: `10.8.0.0/16`, `192.168.99.0/24`

### `ep_gateway`

Required: only if `ep_strict=1`

Address within `ep_network` that points to the server itself.
Only required if strict mode is enabled.

Examples: `10.8.0.1`, `192.168.99.1`

### `ep_device`

Required: no

Default: `tun+`

Device name allpwed for this endpoint.
Supports iptables device name globs.
By default any device starting with "tun" is allowed

### `ep_strict`

Required: no

Default: 0

Set to 1 to enable strict mode for this endpoint.
Explanatiln of strict mode can be founs in README

### `ep_strict_udp`, `ep_strict_tcp`

Required: no

Default: *empty*

Strict mode port whitelist for corresponding protocols.
Multiple ports can be specified separated by comma.
Have effect only if `ep_strict=1`.

Examples: `1120,1337,2001`, `6003`

### `ep_strict_icmp`

Reauired: no

Default: 1

Allow icmp packets bw passed trough real interface

## Miscellaneous

These are general options. They can be specified anywhere in config file
and don't need to be commited. None of them are required.

### `WHITELIST`

Default: *empty*

Simple IP address whitelist (comma speatared). These addresses will be allowed to reach
trough the real interface while VPN client is down and it's routes are absent.

### `FINAL_RULE`

Default: `DROP`

Defines target (`-j`) for final rule for filter chain which decides the fate of all non-matched packets.
This option allows you to specify multiple arguments if you target needs it

Examples:
- `my_own_chain` - continue processing of packet in other chain
- `RETURN` - return the packet to parent chain
- `REJECT --reject-with addr-unreach` - multiple arguments are allowed

### `INSERT_TO`

Default: `A`

Position (number) to insert the jump rule (the one injected on enabling) to embeded chain(s).
`A` is a special value telling that jump rule should be appended, not inserted.
Applies for both filter chain and nat chains.

Examples:
- `A` - append jump rules to the end
- `0` - insert jump rules to beginnng

### `CHAIN`

Default: `ovpn_leak`

Name of the chain with actual rules generated on setup.
Jump to this chain will be injected to filter OUTPUT on enabling (see `INSERT_TO` above).
If nat table is needed, names for nat chains will be derived from it, adding `_nat_out` and `_nat_post` suffixes.

### Embedded chains override

Default:
- `CHAIN_OUTPUT`: `OUTPUT`
- `CHAIN_NAT_OUTPUT`: `OUTPUT`
- `CHAIN_NAT_POSTROUTING`: `POSTROUTING`

Defines the chains where jump rules will be inserted. If you have your own rule set you might want to override defaults
and force the script to insert jump rules to your own chains on enable/disable.


