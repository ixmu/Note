#!/bin/bash

# Check Root User

# If you want to run as another user, please modify $EUID to be owned by this user
if [[ "$EUID" -ne '0' ]]; then
    echo "$(tput setaf 1)Error: You must run this script as root!$(tput sgr0)"
    exit 1
fi

# Set the desired GitHub repository
raw_base_url="https://raw.ixnic.net"
download_base_url="https://download.ixnic.net"
version="3.0.0-nightly.20240801"

# Function to download and install gost
install_gost() {
    version=$1
    # Detect the operating system
    if [[ "$(uname)" == "Linux" ]]; then
        os="linux"
    elif [[ "$(uname)" == "Darwin" ]]; then
        os="darwin"
    elif [[ "$(uname)" == "MINGW"* ]]; then
        os="windows"
    else
        echo "Unsupported operating system."
        exit 1
    fi

    # Detect the CPU architecture
    arch=$(uname -m)
    case $arch in
    x86_64)
        cpu_arch="amd64"
        ;;
    armv5*)
        cpu_arch="armv5"
        ;;
    armv6*)
        cpu_arch="armv6"
        ;;
    armv7*)
        cpu_arch="armv7"
        ;;
    aarch64)
        cpu_arch="arm64"
        ;;
    i686)
        cpu_arch="386"
        ;;
    mips64*)
        cpu_arch="mips64"
        ;;
    mips*)
        cpu_arch="mips"
        ;;
    mipsel*)
        cpu_arch="mipsle"
        ;;
    *)
        echo "Unsupported CPU architecture."
        exit 1
        ;;
    esac

    mkdir -p /tmp/gost && cd /tmp/gost/
    download_url="${download_base_url}/go-gost/gost/releases/download/v${version}/gost_${version}_${os}_${cpu_arch}.tar.gz"

    # Download the binary
    echo "Downloading gost version $version..."
    curl -fsSL -o gost.tar.gz $download_url

    curl -fsSL -o /etc/systemd/system/gost.servic "${raw_base_url}/ixmu/Note/master/gost/gost.service"
    mkdir -p /etc/gost/
    touch /etc/gost/config.yaml

    # Extract and install the binary
    echo "Installing gost..."
    tar -xzf gost.tar.gz
    chmod +x gost
    mv gost /usr/local/bin/gost

    echo "gost installation completed!"
    
    echo "wss入口点简单配置生成 gost -L tcp://:中转机入站端口 -F relay+wss://中转机IP:中转机出站端口 -O yaml"
    echo "wss出口点简单配置生成 gost -L relay+wss://:中转机出站端口/落地机IP:落地机端口 -O yaml"
}

install_gost ${version}
