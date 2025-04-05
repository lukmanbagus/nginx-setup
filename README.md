# Nginx Domain Setup Script
A bash script for automatically installing and configuring Nginx web server with custom domain settings on Ubuntu 22.04.

## Overview
This script automates the process of setting up a new website with Nginx on Ubuntu 22.04. It handles the entire workflow from installing Nginx, creating the necessary directory structure, configuring server blocks, and optionally setting up SSL certificates using Let's Encrypt.

## Features

- Dynamically configure any domain name
- Automatic Nginx installation and configuration
- Creation of website directory structure with proper permissions
- Generation of a basic HTML test page
- Configuration of Nginx server blocks
- Automatic firewall configuration (if UFW is active)
- Optional SSL certificate installation via Let's Encrypt/Certbot
- Interactive confirmation before installation begins
- Comprehensive validation of required parameters

## Requirements

- Ubuntu 22.04 LTS (Jammy Jellyfish)
- Root or sudo privileges
- Internet connection for package installation
- Domain with DNS A record pointing to your server's IP address

## Usage
### 1. Clone repo
```
git clone git@github.com:lukmanbagus/nginx-setup.git && cd nginx-setup
```
### 2. Add executable
```
chmod +x setup.sh
```
### 3. Run script with enter your domain and email to install SSL
```
sudo ./setup.sh --domain=yourdomain.com --ssl --email=your@email.com
```
