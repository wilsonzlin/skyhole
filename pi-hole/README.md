# Pi-hole

Pi-hole is a convenient DNS server that can block requests to unwanted domains through managed and custom lists. It comes with a web interface that provides insights about queries and management of the server.

This setup uses DNS-over-TLS to serve and forward DNS queries for more privacy. It also secures the web interface with HTTPS only.

## Components

### Nginx

Nginx creates a TLS proxy to serve DNS-over-TLS requests and send them to the Pi-hole DNS server.

### Stubby

Stubby is used as the upstream DNS for Pi-hole so that queries from Pi-hole that it cannot answer are done using DNS-over-TLS.

### Let's Encrypt

Let's Encrypt provides and automatically renews TLS certificates for the DNS-over-TLS server and Pi-hole web interface.

## Server

### Prerequisites

### Install

### Usage

## Client

### Windows

### macOS

### Linux

### Android
