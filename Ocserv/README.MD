# ocserv.sh Debian x64 12)
```
bash <(wget --no-check-certificate --no-cache -4 -qO- "https://raw.githubusercontent.com/ixmu/Note/refs/heads/master/Ocserv/ocserv_install.sh")
```

# 使用 BBR 加速纯 TCP 模式的流量
```
bash <(wget --no-check-certificate -qO- 'https://raw.githubusercontent.com/moeclub/apt/master/bbr/bbr.sh')

```
# 推荐Docker运行
```
docker run --name ocserv --privileged --restart always -e "NoRoute=abc:123" -d -p 443:443 ocserv/ocserv
docker run --name ocserv --privileged --restart always -v /mnt/ocserv:/mnt -d -p 443:443 ocserv/ocserv
docker run --name ocserv --privileged --restart always -v /etc/ocserv:/etc/ocserv -v /etc/dnsmasq.d:/etc/dnsmasq.d --network podmanv6 -d -p 2443:443 ocserv/ocserv
docker run --privileged --rm -it -p 443:443/tcp -p 443:443/udp ocserv/ocserv

```
