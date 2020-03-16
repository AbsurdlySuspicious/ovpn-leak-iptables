# ovpn-leak
  
This is a simple script for installing, enabling and disabling set of
iptables rules preventing packets from leaking to your real gateway.
It's meant to be used with openvpn, but will work with any 
tun device based vpn clients. 

## Rationale

A common problem with openvpn is that any reconnection,
including internal routines like `ping-restart`, includes removal
of tun device as well as routes overriding your real gateway. It leads to
outgoing packets may leak to your real network interface during reconnection
which is not always acceptable. `persist-tun` option is suposedly
meant to address this issue but also inhibits any internal restart routines regardless
of any \*restart options set in config, meaning that your openvpn client instance
will hang forever in case of server restart or connection problems,
not being able to reconnect or restore current vpn connection.

This script is meant to actually address this issue by dropping any outgoing packets
not routed through allowed tun device so you can use any reconnect/restart solution you like
without worrying about leaks.

## How it works

On `setup` command this script creates new iptables chain that will ACCEPT **only** those packets:
- packets going to the tun interface with source IP inside your VPN subnet
- packets going to your endpoint (VPN server) address (You can specify multiple endpoints and subnets)
- packets going to RFC 1918 private subnets and localhost (192.168.0.0/16, 10.0.0.0/8, 172.16.0.0/12, 127.0.0.0/8)
- packets within established connections

That means any packets going to the (routable) internet addresses not through your VPN
will be dropped, but any packets to going private subnets (like your physical local network) and input connections 
will be allowed. Check the [rules  example](RULES_EXAMPLE.md) for details.

On `on` command script will inject this chain to `filter` table's OUTPUT chain,
and also optionally another chain to `nat`'s OUTPUT and POSTROUTING chains (see below).
Be careful to check for any conflicts before enabling those chains of you're already using 
your own iptables rules.

### Strict endpoints

By default any traffic to endpoint address is routed through your real gateway.
Even when vpn client is working, any connections to for example ssh (22) or http (80)
server on the same address will bypass vpn and go through yout physical network interface.

If you enable strict mode for an endpoint, you should specify ports that your
VPN client is using to allow them to go through real gateway.
Then any non-whitelisted ports will be routed to specified
VPN gateway address (e.g. 10.8.0.1 for 10.8.0.0/24). This mechanism
uses DNAT and MASQUERADE targets of iptables `nat` table.
On the contrary, if strict mode is enabled, you won't be able
to reach non-whitelisted ports when rules are enabled and VPN client isn't working.

## Usage

Before using the script, you should specify all endpoints (VPN servers)
you'll be using in config, as well as some optional parameters if you need it.
Consult the [config help](CONFIG_HELP.md) and [config exmaple](example_config)
for detailed explanation of each option and reference.

Usage:

```
Usage: ovpn-leak [-c <CONFIG>] <MODE>
Modes: setup, clear, on, off
```

If you won't specify `-c` option, script will use
default config path: `$XDG_CONFIG_HOME/ovpn-leak/config` (usually expands to `~/.config/ovpn-leak/config`)

Modes:
- `setup` will perform initial rules setup, but won't enable them
- `on` / `off`  will enable/disable blocking rules. You should run `setup` before enabling the rules.
- `clear` will disable and completely delete any rules created during setup. After this, you should run `setup` again before using the script again.

Commands `on`, `off`, and `clear` should be run with the same config used for `setup` before.

If you want to edit config, you should call `clear` before this, and then call `setup` again after edit.

If you already edited or replaced the config but forgot to call `clear` beforehand, you still can call
`clear` with the new config as long as you haven't changed any chains names, otherwise you should clean the rules manually.

In any case, after any config changes you should run `setup` and `on` again, otherwise new config won't take the effect.


### Making changes permamnent

There's two ways to make the rules permanent:
1. Add `ovpn-leak setup` and `ovpn-leak on` commands to to autorun according to your disto guidelines
2. Use `iptables-save`

If you're using iptables save, you should re-save the rules after any config change.
Distributions usually come with the startup script that will load saved rules. There is some examples:

**Arch Linux:**

```
# ovpn-leak setup
# ovpn-leak on
# iptables-save > /etc/iptables/iptables.rules
# systemctl enable iptables.service
```

**Ubuntu:**

```
# apt install iptables-persistent netfilter-persistent
# ovpn-leak setup
# ovpn-leak on
# iptables-save > /etc/iptables/rules.v4
# systemctl enable netfilter-persistent.service
```

## Installation

Script is usable as-is, but for convinience you can:

**Put your config to default path**

You can put your config to the file as specified in [Usage](#usage) section,
so you won't need to specify `-c` option every time you use the script

**Add script to your PATH**

You can add directory where the repo is cloned to your path, for example:

```
~ > git clone XXX .local/share/ovpn-leak
~ > echo 'PATH=$PATH:$HOME/.local/share/ovpn-leak' >> .bashrc
```

## License

This repository is licensed under MIT

Check [LICENSE](LICENSE) file for details

