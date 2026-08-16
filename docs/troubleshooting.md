# Troubleshooting

## 1. SideStore still reports DeviceEndpointNotInitialized

Check SideStore Connection Configuration first. This release expects:

```text
Override Peer IP: 10.7.0.1
```

Then verify the router target:

```sh
grep '^TARGET=' /data/xiaomi-router-7day-refresh.conf
```

Expected:

```text
TARGET="10.7.0.1"
```

Restart the router helper and renew Wi-Fi DHCP:

```sh
START_DELAY=2 /data/xiaomi-router-7day-refresh-start.sh
```

Toggle iPhone Wi-Fi OFF/ON once, then check Health Check / Refresh again.

## 2. Repeater mode does not inject the route

Check:

```sh
/data/xiaomi-router-7day-refresh-status.sh
```

Expected DHCP log:

```text
learned iPhone ingress interface: wl...
INJECTED DHCP ACK ... Option121 10.7.0.1/32 via <child-router-ip> + default via <upstream-gateway>
```

If the ingress interface is never learned, verify the iPhone Wi-Fi MAC in `/data/xiaomi-router-7day-refresh.conf`, then reconnect Wi-Fi.

## 3. Main-router mode does not inject the route

Confirm the project-owned dnsmasq snippet exists and the configured `DNSMASQ_CONF_DIR` matches the active generated dnsmasq configuration.

Capture DHCP:

```sh
/data/xiaomi-router-7day-refresh-diagnose.sh watch-dhcp
```

The ACK for the configured iPhone should contain Classless-Static-Route / Option 121.

## 4. iPhone cannot get an IP in repeater mode

Immediately stop the project:

```sh
/data/xiaomi-router-7day-refresh-cleanup.sh
```

The cleanup script removes the DHCP ACK interception chain before stopping the injector to avoid a DHCP black-hole. Then reconnect Wi-Fi and verify normal DHCP.

## 5. DHCP injection works but no SideStore target traffic reaches the router

Run:

```sh
/data/xiaomi-router-7day-refresh-diagnose.sh watch-target
```

Trigger SideStore Health Check or Refresh. The router should see `10.7.0.1` traffic.

Also check:

```sh
ip route get 10.7.0.1
```

The router-side route should use the `sidestore` TUN interface.

## 6. Legacy v0.4 state remains

v0.5 start/cleanup removes legacy `198.19.0.2` project routes and bypass rules. If upgrading manually, run:

```sh
/data/xiaomi-router-7day-refresh-cleanup.sh
```

before starting v0.5.
