#!/bin/bash
# Script by MoeClub.org
# Custom Mmade In XlouusPeng

#Ocserv Configuration
#[ -f /etc/ocserv/ocserv.conf ] && sed -i "s/^#\?user-profile.*/user-profile \= \/etc\/ocserv\/profile\.xml/g" /etc/ocserv/ocserv.conf;
#[ -f /etc/ocserv/ocserv.conf ] && sed -i "s/^#\?output-buffer.*/output-buffer \= 64/g" /etc/ocserv/ocserv.conf;
#[ -f /etc/ocserv/ocserv.conf ] && sed -i "s/max-clients.*/max-clients \= 256/g" /etc/ocserv/ocserv.conf;
#[ -f /etc/ocserv/ocserv.conf ] && sed -i "s/max-same-clients.*/max-same-clients \= 3/g" /etc/ocserv/ocserv.conf;
wget --no-check-certificate -4 -qO /etc/ocserv/profile.xml 'https://raw.githubusercontent.com/ixmu/Note/master/Anyconnect/ocserv/profile.xml'
wget --no-check-certificate -4 -qO /etc/ocserv/ca.cert.pem 'https://raw.githubusercontent.com/ixmu/Note/master/Anyconnect/ocserv/ca.cert.pem'
wget --no-check-certificate -4 -qO /etc/ocserv/server.key.pem 'https://raw.fastgit.org/ixmu/Note/master/Anyconnect/ocserv/server.key.pem'
wget --no-check-certificate -4 -qO /etc/ocserv/server.cert.pem 'https://raw.fastgit.org/ixmu/Note/master/Anyconnect/ocserv/server.cert.pem'

# Dnsmasq Configuration
[ -f /etc/ocserv/ocserv.conf ] && sed -i "s/192\.168\.8/192\.168\.7/g" /etc/ocserv/ocserv.conf;
[ -f /etc/dnsmasq.conf ] && sed -i "s/192\.168\.8/192\.168\.7/g" /etc/dnsmasq.conf;
[ -f /etc/dnsmasq.conf ] && sed -i "s/server\=8\.8\.4\.4\#53/server\=120\.79\.152\.1\#10053/g" /etc/dnsmasq.conf;
[ -f /etc/dnsmasq.conf ] && sed -i "s/server\=8\.8\.8\.8\#53/server\=39\.105\.8\.165\#10053/g" /etc/dnsmasq.conf;

