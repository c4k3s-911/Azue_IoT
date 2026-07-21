# Installation Guide

## Prerequisites

### On VPS (Home Base)
- Ubuntu 24.04 LTS (or similar)
- WireGuard
- SSH server
- Basic tools: curl, wget, rsync

### On N950 (Field Device)
- Termux (Android terminal emulator)
- WSL/PRoot Debian container
- nmap or rustscan
- Bash 4.0+

## Quick Setup

### 1. Clone this Repository

```bash
git clone https://github.com/c4k3s-911/Azue_IoT.git
cd Azue_IoT
```

### 2. Install Dependencies

#### On Debian/Ubuntu:
```bash
sudo apt update
sudo apt install -y nmap xsltproc xmllint wireguard-tools
```

#### On Alpine:
```bash
apk add --no-cache nmap xsltproc xmllint wireguard-tools
```

#### On Termux (N950):
```bash
pkg install -y nmap xsltproc xmllint wireguard-tools
```

### 3. Make Scripts Executable

```bash
chmod +x report_gen.sh 0xsec_recon.sh verify_pipeline.sh
```

### 4. Test Installation

```bash
# Verify report generator
./report_gen.sh --version

# Create test XML
cat > /tmp/test.xml << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<nmaprun version="Nmap (7.94SVN)" timestamp="1720000000">
  <host starttime="1720000000" endtime="1720000001">
    <address addr="192.168.1.100" addrtype="ipv4"/>
    <ports><port protocol="tcp" portid="22"><state state="open"/></port></ports>
  </host>
</nmaprun>
EOF

# Test report generation
./report_gen.sh -v /tmp/test.xml

# Should output: test_report.md
cat /tmp/test_report.md
```

## Configuration

### WireGuard Setup (VPS)

```bash
# Generate keys
wg genkey | tee /tmp/privatekey | wg pubkey > /tmp/publickey

# Create wg0.conf
sudo tee /etc/wireguard/wg0.conf > /dev/null <<EOF
[Interface]
Address = 10.8.0.1/24
ListenPort = 51820
PrivateKey = $(cat /tmp/privatekey)
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE

EOF

# Enable and start
sudo systemctl enable wg-quick@wg0
sudo systemctl start wg-quick@wg0
```

### WireGuard Setup (N950)

```bash
# Copy config from VPS
adb push wg0.conf /sdcard/

# In Termux
mkdir -p ~/.wireguard
cp /sdcard/wg0.conf ~/.wireguard/
chmod 600 ~/.wireguard/wg0.conf

# Activate tunnel
wg-up  # Custom script, or use: sudo wg-quick up wg0
```

## Troubleshooting

### Missing xsltproc
```bash
# Check if installed
which xsltproc

# Install
sudo apt install xsltproc  # Debian/Ubuntu
apk add xsltproc           # Alpine
pkg install xsltproc       # Termux
```

### Report Won't Generate
```bash
# Check XML validity
xmllint --noout /path/to/scan.xml

# Enable verbose mode
./report_gen.sh -v /path/to/scan.xml

# Force processing of broken XML
./report_gen.sh --force /path/to/scan.xml
```

### WireGuard Tunnel Issues
```bash
# Test connectivity
wg show

# Verify routing
ip route | grep 10.8

# Check logs
sudo journalctl -u wg-quick@wg0 -n 50
```
