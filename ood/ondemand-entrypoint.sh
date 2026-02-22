#!/bin/bash
set -e

echo "---> Starting the MUNGE Authentication service (munged) ..."
chown -R munge:munge /etc/munge
chmod 0700 /etc/munge
chmod 0600 /etc/munge/munge.key 2>/dev/null || true
sudo -u munge /usr/sbin/munged

echo "---> Waiting for slurmctld to become active ..."
until 2>/dev/null >/dev/tcp/slurmctld/6817
do
    echo "-- slurmctld is not available. Sleeping ..."
    sleep 2
done
echo "-- slurmctld is now active ..."

echo "---> Configuring OnDemand portal ..."
/opt/ood/ood-portal-generator/sbin/update_ood_portal --insecure

echo "---> Generating SSL certificates ..."
/usr/libexec/httpd-ssl-gencerts 2>/dev/null || true

echo "---> Starting SSH server ..."
ssh-keygen -A
rm -f /var/run/nologin /run/nologin /etc/nologin
/usr/sbin/sshd

echo "---> Starting ondemand-dex ..."
cd /usr/share/ondemand-dex
sudo -u ondemand-dex /usr/sbin/ondemand-dex serve /etc/ood/dex/config.yaml &
cd /

echo "---> Starting Apache httpd for OnDemand ..."
/usr/sbin/httpd -DFOREGROUND
