---
layout: post
title: "Making ssh -D use a specific outbound interface"
tags: networking english
---

## Context
{% asciiart center %}
                                                       .----------------.
                        .-------------------.       .--|    devices     |
  .--------.        .---'--.            .---'---.  /   '----------------'
  | client |-[SSH]->| eth0 |   server   | wlan0 |-<
  '--------'        '---.--'            '---.---'  \   .----------------.
172.16.100.101          '-------------------'       '--| captive portal |
                         eth0: 172.16.200.201          '----------------'
                         wlan0: 10.10.10.10
{% endasciiart %}

I needed to analyze a captive portal locally, while the actual WiFi connection
lived on `server`.

Problem: `ssh -D X user@server` gives me a SOCKS endpoint on the client, but it
doesn't control which interface `server` uses for outbound connections. On this
specific setup, outbound flows follow the host routing policy (usually `eth0`),
so the portal never appears.

> Why not just curl from the server, get the portal IP, then add routes?

You _can_, but it's annoying:

- Captive portals are often not a single fixed IP (redirect chains, CDNs, multiple domains, etc....).
- If you roam across many WiFi networks, you don't want a _"per-network discover IPs, add routes, clean up routes"_ workflow.
- A wrong route can leak traffic out eth0. This is not really a problem, but why bother even having to deal with this :).

So instead of chasing portal endpoints, I forced all SOCKS egress to use `wlan0`, regardless of what the portal does.


## My overcomplicated fix: policy routing only for the SOCKS user (on server)

### 1. Dedicated user for the tunnel

{% highlight bash %}
root@server$ useradd -m -s /bin/bash socks
{% endhighlight %}

### 2. Create a routing table (100) with default via wlan0

{% highlight bash %}
root@server$ WLAN_GW=$(ip route show default dev wlan0 | awk '{print $3}')
root@server$ WLAN_NET=$(ip -o -f inet route show dev wlan0 scope link | awk '{print $1}')

root@server$ ip route flush table 100
root@server$ ip route add "$WLAN_NET" dev wlan0 scope link table 100
root@server$ ip route add default via "$WLAN_GW" dev wlan0 table 100
{% endhighlight %}

### 3. Mark traffic owned by user socks

{% highlight bash %}
root@server$ iptables -t mangle -A OUTPUT -m owner --uid-owner socks -j MARK --set-mark 0x1
{% endhighlight %}

### 4. Route marked packets using table 100

{% highlight bash %}
root@server$ ip rule add fwmark 0x1 lookup 100 priority 100
{% endhighlight %}

### 5. Start SOCKS from my client to server

{% highlight bash %}
user@client$ ssh -N -D 127.0.0.1:7890 socks@172.16.200.201
{% endhighlight %}

### 6. tcpdump check

From the client:

{% highlight bash %}
user@client$ curl -ki --socks5-hostname 127.0.0.1:7890 https://blog.kippel.org
HTTP/1.1 302 Captive Portal
Server:
Date: Wed, 21 Dec 2022 10:04:43 GMT
Cache-Control: no-cache,no-store,must-revalidate,post-check=0,pre-check=0
Location: https://portal.example.com:443/guest/arubalogin.php?cmd=login&...&ip=172.16.200.201&url=https%3A%2F%2Fblog.kippel.org%2F
Content-Type: text/html; charset=utf-8
X-Frame-Options: SAMEORIGIN
X-XSS-Protection: 1; mode=block
X-Content-Type-Options: nosniff
Strict-Transport-Security: max-age=604800
Connection: close

<HTML>
<HEAD><TITLE>302 Captive Portal</TITLE></HEAD>
<BODY BGCOLOR="#cc9999" TEXT="#000000" LINK="#2020ff" VLINK="#4040cc">
<H4>302 Captive Portal</H4>

<ADDRESS><A HREF="http://www.arubanetworks.com"></A></ADDRESS>
</BODY>
</HTML>
{% endhighlight %}

From the server:

{% highlight bash %}
root@server$ tcpdump -i wlan0 -n
tcpdump: verbose output suppressed, use -v[v]... for full protocol decode
listening on wlan0, link-type EN10MB (Ethernet), snapshot length 262144 bytes
...
15:01:42.855746 IP 10.10.10.10.45301 > 10.10.10.1.53: 18557+ A? blog.kippel.org. (29)
15:01:42.870100 IP 10.10.10.1.53 > 10.10.10.10.45301: 18557 1/0/0 A 104.21.34.11 (45)
15:01:42.889385 IP 10.10.10.10.60302 > 104.21.34.11.443: Flags [S], seq 712479030, win 64240, options [mss 1460,sackOK,TS val 1789227809 ecr 0,nop,wscale 10], length 0
15:01:42.890882 IP 104.21.34.11.443 > 10.10.10.10.60302: Flags [S.], seq 2006562653, ack 712479031, win 24960, options [mss 1260,sackOK,TS val 1556975851 ecr 1789227809,nop,wscale 7], length 0
15:01:42.890934 IP 10.10.10.10.60302 > 104.21.34.11.443: Flags [.], ack 1, win 63, options [nop,nop,TS val 1789227811 ecr 1556975851], length 0
...
{% endhighlight %}

### 7. Cleanup

{% highlight bash %}
root@server$ ip rule del fwmark 0x1 lookup 100
root@server$ iptables -t mangle -D OUTPUT -m owner --uid-owner socks -j MARK --set-mark 0x1
root@server$ ip route flush table 100
root@server$ userdel -r socks
{% endhighlight %}

### Bonus: auto-rebuild table 100 when WiFi changes

When connecting to a new network, `ip rule` and the packet marking stays the same, only `table 100` needs to be rebuilt.

{% highlight bash %}
root@server$ cat /usr/local/sbin/rebuild-table100.sh
#!/usr/bin/env bash
set -euo pipefail

IFACE="$1"
TABLE=100

# Horrible way to wait for new default gateway and subnrt
GW=""
NET=""
for _ in {1..30}; do
   GW=$(ip route show default dev "$IFACE" | awk '{print $3}' || true)
   NET=$(ip -o -f inet route show dev "$IFACE" scope link | awk '{print $1}' || true)
   [[ -n "$GW" && -n "$NET" ]] && break
   sleep 1
done
[[ -n "$GW" && -n "$NET" ]] || exit 0

ip route flush table "$TABLE"
ip route add "$NET" dev "$IFACE" scope link table "$TABLE"
ip route add default via "$GW" dev "$IFACE" table "$TABLE"
{% endhighlight %}

{% highlight bash %}
root@server$ cat /etc/NetworkManager/dispatcher.d/90-table100
#!/bin/sh
IFACE="$1"
ACTION="$2"

case "$IFACE:$ACTION" in
   wlan0:up|wlan0:dhcp4-change|wlan0:dhcp6-change)
      /usr/local/sbin/rebuild-table100.sh wlan0
      ;;
   wlan0:down)
      ip route flush table 100
      ;;
esac
{% endhighlight %}
