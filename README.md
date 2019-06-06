# TLD Name Server Configuration
The attached Dockerfile builds a new container running Bind9 that is intended to host the fake TLD we are using for our projects. By configuing the TLD zone on one of the routers in your group, you'll enable your local resolvers to discover the authoritative servers for each domain.

This image can be used as a general purpose bind server by mapping your own named.conf and other configuration files into /etc/bind of the container.

## Install Docker (Raspbian Stretch)
The easiest method of installing Docker on a Raspberry Pi running Raspbian, is to execute a scripted install from the Docker website. 

1. `curl -sSL get.docker.com | sh` to install Docker
2. `sudo usermod -aG docker pi` to allow the pi user to manage Docker
3. `echo gpu_mem=16 | sudo tee -a /boot/config.txt` to decrease memory reserved for graphics operations (Optional step to improve performance)

## Build the container image
From the directory with the docker file, run `docker build -t dotpi .`.

## Create an automated task for zone updates
The zonefile included in the base container will not be up-to-date, but the latest version of this file can be downloaded from https://gist.githubusercontent.com/clintoncampbell/ee3ce5e1826315cf1e6659f3c0dccd9c/raw.

To ensure that you are always running with the latest version of the database, I recommend that you automate a download. Within Linux, _cron_ is responsible for running recurring tasks. We can set up our own tasks within _cron_ by editing the _crontab_ with `crontab -e`. 

Follow the steps below to configure the root user to download the zone into `/etc/dotpi` once every 30 minutes:

- `sudo mkdir -p /etc/dotpi/zones`
- `sudo crontab -e`
-- Insert a new line in the crontab containing `*/30 * * * * wget -O /etc/dotpi/zones/db.pi https://gist.githubusercontent.com/clintoncampbell/ee3ce5e1826315cf1e6659f3c0dccd9c/raw`
-- Save and exit
- Confirm that the file has been downloaded to `/etc/dotpi/zones/db.pi`

## Configure the TLD IP address
Per the project instructions, the .pi TLD will run at 10.10.10.10. Since we're running BGP, we can configure the address to be resolved from multiple locations on the LAN (approximating the Anycast configuration that is often used for hosting critical domain services).

### Create a dummy interface
`/etc/systemd/network/25-dummy1.netdev`
```
[NetDev]
Name=dummy1
Kind=dummy
```
Confirm that _systemd networking_ is enabled by running `sudo systemctl enable systemd-networkd`. Restart the service to configure your dummy interface with `sudo systemctl restart systemd-networkd`.

### Configure addressing
Run the following commands within VTY shell:
```
configure terminal
interface dummy1
ip address 10.10.10.10/32
```

## Configure BGP to advertise 10.10.10.10
This section assumes that you have previously configured BGP and peered it to at least one other router. In the commands below, substitute `_ASN_` for the Autonomous System Number you used when setting up BGP initially. You can review your previous settings by executing `show run` from the _enable_ prompt of VTY shell.

Run the following commands within VTY shell:
```
configure terminal
router bgp _ASN_
network 10.10.10.0/24
```

Note that we are advertising the full /24 for the anycast address. In production systems, prefixes larger than /24 are often filtered from BGP advertisements in order to constrain the size of the Internet routing tables. As such, a full /24 is used as a _covering prefix_ for the Anycast address.

## Launch the container
Use Docker to run the container and bind it to port 53 (udp+tcp). Note that we also mapped our /etc/dotpi/zones directory into the container at /etc/bind/zones so that the named instance running inside the container will pick up the updates retrieved by the cron job on the host.

`docker run -d --restart always --name dotpi -v /etc/dotpi/zones:/etc/bind/zones -p 10.10.10.10:53:53/udp -p 10.10.10.10:53:53/tcp dotpi`

## Configure resolvers
Since .pi is not discoverable at the ICANN root zone, we need to update our caching resolvers to recognize the zone and send queries to 10.10.10.10.

Add the following section to your `/etc/bind/named.conf.local`. If you've configured separate views for internal and external name resolution, this will be inserted into the internal view.

```
zone "pi" IN {
  type slave;
  masters { 10.10.10.10; };
};
```
