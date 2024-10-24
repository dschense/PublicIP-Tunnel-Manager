# PublicIP-Tunnel-Manager
Bash scripts for managing public IP tunnels via GRE or Wireguard to route public IP to your home router

# READ THE WIKI

## What to do
tunnel.sh --> manual start/stop in terminal  
tunnel-service.sh --> without tput/color to run as systemd service (for auto connect on startup)  

1. Download the zip
2. copy tunnel.service to /etc/systemd/system
3. change the path to your tunnel-service.sh
4. systemctl daemon-reload
5. systemctl start/stop tunnel.service
6. systemctl enable tunnel.servide

All Credits to ©KernelMaker - aka. ©MokkaSchnalle - https://github.com/MokkaSchnalle  
https://administrator.de/tutorial/feste-ips-zuhause-in-pfsense-via-wireguard-tunnel-1124828094.html  

Just did some little changes.
