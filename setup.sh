#!/bin/sh

echo "Setting up system..."

if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi

echo "Installing necessary packages."

dnf -y install vim-enhanced realmd samba samba-common samba-winbind-clients samba-common-tools samba-winbind-krb5-locator oddjob oddjob-mkhomedir bash-completion bind-utils krb5-workstation 2>&1 > /dev/null

echo "Updating all packages."

dnf -y update 2>&1 > /dev/null

echo "Set SELinux policy to permissive."

sed -i s/^SELINUX=.*$/SELINUX=permissive/ /etc/selinux/config
setenforce 0 2>&1 > /dev/null

echo "Enter active directory domain to join (eg. itgrp.dk)"
read -p "Domain: " domain

domain=$(echo "$domain" | tr '[:lower:]' '[:upper:]')

echo "Enter domain username without domain."
echo "For this to work, make sure that DNS servers are DC IP's."

read -p "Username: " username

kinit $username@$domain

exit

echo "Setting IP address".
echo "Leave blank to try to auto-detect. Will only work with one interface."

read -p "IP address: " ipaddr

if [ -z "$ipaddr" ]
  # Auto-detect IP address
  then
    echo "$(ip addr show dev $(ip r | grep -oP 'default.*dev \K\S*') | grep -oP '(?<=inet )[^/]*(?=/)') $(hostname -f) $(hostname -s)" >> /etc/hosts
  else
    read -p "Hostname (without itgrp.dk): " hostname
    echo "$ipaddr $hostname.itgrp.dk $hostname" >> /etc/hosts
fi

echo "Joining domain."

realm join --membership-software=samba --client-software=winbind itgrp.dk

echo "Changing default login mechanism."

authselect select winbind with-mkhomedir with-pamaccess --force

echo "Changing access security configuration."

sed -i 's/pam_access\.so/pam_access\.so listsep=,/g' /etc/pam.d/password-auth
sed -i 's/pam_access\.so/pam_access\.so listsep=,/g' /etc/pam.d/system-auth

echo -e "#\n# Allow only root from localhost or domain admins from any host\n+:root:LOCAL\n+:domain admins:ALL\n# All other users should be denied to get access from all sources.\n-:ALL:ALL" >> /etc/security/access.conf

echo "Set template homedir and defalt domain."

sed -i 's/^template homedir = .*$/template homedir = \/home\/%U/' /etc/samba/smb.conf
sed -i 's/^winbind use default domain = .*$/winbind use default domain = yes/' /etc/samba/smb.conf

echo "Restart SAMBA".

systemctl restart smb
systemctl restart winbind

echo "Setting up sudoers."

echo -e "%domain\ admins           ALL=(ALL)       NOPASSWD:ALL" > /etc/sudoers.d/itgrp

echo "Set default bash settings."

sed -i "$ i\ \nif [ \$(id -u) -eq 0 ];\nthen\n  export PS1='\\\[\\\033[01;31m\\\][\${USER%@*}@\\\h]:\\\w #\\\[\\\033[0m\\\] '\nelse\n  export PS1='\\\[\\\033[01;32m\\\][\${USER%@*}@\\\h]:\\\[\\\033[01;31m\\\]\\\w $\\\[\\\033[0m\\\] '\nfi\n\nexport HISTTIMEFORMAT='%y-%m-%d %T '\nexport HISTSIZE=100000\nexport HISTFILESIZE=20000\nexport HISTCONTROL=ignoreboth:erasedups" /etc/bashrc

echo "Enable automatic updates."

dnf -y install dnf-automatic yum-utils 2>&1 > /dev/null

sed -i 's/^apply_updates = .*$/apply_updates = yes/' /etc/dnf/automatic.conf

systemctl enable --now dnf-automatic.timer

echo -e "#Check needs restarting every day  at 4.30 AM\n30 4 * * * /usr/bin/needs-restarting -r || /usr/sbin/shutdown -r" >> /var/spool/cron/root

systemctl reload crond

echo "System settings done!"
