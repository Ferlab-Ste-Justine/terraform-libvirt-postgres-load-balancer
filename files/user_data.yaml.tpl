#cloud-config
%{ if admin_user_password != "" ~}
chpasswd:
  list: |
     ${ssh_admin_user}:${admin_user_password}
  expire: False
%{ endif ~}
preserve_hostname: false
hostname: ${node_name}
users:
  - default    
  - name: node-exporter
    system: True
    lock_passwd: True
  - name: ${ssh_admin_user}
    ssh_authorized_keys:
      - "${ssh_admin_public_key}"
write_files:
  #Patroni tls files for health checks
  - path: /opt/patroni/ca.pem
    owner: root:root
    permissions: "0444"
    content: |
      ${indent(6, haproxy.patroni_client.ca_certificate)}
  - path: /opt/patroni/client.pem
    owner: root:root
    permissions: "0400"
    content: |
      ${indent(6, "${patroni_client_certificate}\n${patroni_client_key}")}
  #Postgres load balancer haproxy configuration
  - path: /opt/haproxy/haproxy.cfg
    owner: root:root
    permissions: "0444"
    content: |
      ${indent(6, haproxy_config)}
  #Chrony config
%{ if chrony.enabled ~}
  - path: /opt/chrony.conf
    owner: root:root
    permissions: "0444"
    content: |
%{ for server in chrony.servers ~}
      server ${join(" ", concat([server.url], server.options))}
%{ endfor ~}
%{ for pool in chrony.pools ~}
      pool ${join(" ", concat([pool.url], pool.options))}
%{ endfor ~}
      driftfile /var/lib/chrony/drift
      makestep ${chrony.makestep.threshold} ${chrony.makestep.limit}
      rtcsync
%{ endif ~}
  #Prometheus node exporter systemd configuration
  - path: /etc/systemd/system/node-exporter.service
    owner: root:root
    permissions: "0444"
    content: |
      [Unit]
      Description="Prometheus Node Exporter"
      Wants=network-online.target
      After=network-online.target
      StartLimitIntervalSec=0

      [Service]
      User=node-exporter
      Group=node-exporter
      Type=simple
      Restart=always
      RestartSec=1
      ExecStart=/usr/local/bin/node_exporter

      [Install]
      WantedBy=multi-user.target
%{ if fluentd.enabled ~}
  #Fluentd config file
  - path: /opt/fluentd.conf
    owner: root:root
    permissions: "0444"
    content: |
      ${indent(6, fluentd_conf)}
  #Fluentd systemd configuration
  - path: /etc/systemd/system/fluentd.service
    owner: root:root
    permissions: "0444"
    content: |
      [Unit]
      Description="Fluentd"
      Wants=network-online.target
      After=network-online.target
      StartLimitIntervalSec=0

      [Service]
      User=root
      Group=root
      Type=simple
      Restart=always
      RestartSec=1
      ExecStart=fluentd -c /opt/fluentd.conf

      [Install]
      WantedBy=multi-user.target
  #Fluentd forward server certificate
  - path: /opt/fluentd_ca.crt
    owner: root:root
    permissions: "0444"
    content: |
      ${indent(6, fluentd.forward_ca_cert)}
%{ endif ~}
packages:
  - apt-transport-https
  - ca-certificates
  - curl
  - gnupg-agent
  - software-properties-common
%{ if fluentd.enabled ~}
  - ruby-full
  - build-essential
%{ endif ~}
%{ if chrony.enabled ~}
  - chrony
%{ endif ~}
runcmd:
  #Finalize Chrony Setup
%{ if chrony.enabled ~}
  - cp /opt/chrony.conf /etc/chrony/chrony.conf
  - systemctl restart chrony.service 
%{ endif ~}
  #Install prometheus node exporter as a binary managed as a systemd service
  - wget -O /opt/node_exporter.tar.gz https://github.com/prometheus/node_exporter/releases/download/v1.3.0/node_exporter-1.3.0.linux-amd64.tar.gz
  - mkdir -p /opt/node_exporter
  - tar zxvf /opt/node_exporter.tar.gz -C /opt/node_exporter
  - cp /opt/node_exporter/node_exporter-1.3.0.linux-amd64/node_exporter /usr/local/bin/node_exporter
  - chown node-exporter:node-exporter /usr/local/bin/node_exporter
  - rm -r /opt/node_exporter && rm /opt/node_exporter.tar.gz
  - systemctl enable node-exporter
  - systemctl start node-exporter
  #Fluentd setup
%{ if fluentd.enabled ~}
  - mkdir -p /opt/fluentd-state
  - chown root:root /opt/fluentd-state
  - chmod 0700 /opt/fluentd-state
  - gem install fluentd
  - gem install fluent-plugin-systemd -v 1.0.5
  - systemctl enable fluentd.service
  - systemctl start fluentd.service
%{ endif ~}
  #Install k8 api load balancer as a background docker container
  - curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
  - add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
  - apt-get update
  - apt-get install -y docker-ce docker-ce-cli containerd.io
  - systemctl enable docker
%{ if fluentd.enabled ~}
  - docker run -d --restart=always --name=postgres_load_balancer --network=host -v /opt/haproxy:/usr/local/etc/haproxy:ro -v /opt/patroni:/opt/patroni/:ro haproxy:2.2.14
%{ else ~}
  - docker run -d --restart=always --name=postgres_load_balancer --network=host -v /opt/haproxy:/usr/local/etc/haproxy:ro -v /opt/patroni:/opt/patroni/:ro --log-driver=fluentd --log-opt fluentd-address=127.0.0.1:28080 --log-opt fluentd-retry-wait=1s --log-opt fluentd-max-retries=3600 --log-opt fluentd-subsecond-precision=true --log-opt tag=${fluentd.load_balancer_tag} haproxy:2.2.14
%{ endif ~}