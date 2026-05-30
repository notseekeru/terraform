terraform {
    required_providers {
    digitalocean = {
        source  = "digitalocean/digitalocean"
        version = "~> 2.0"
    }
    }
}

provider "digitalocean" {
    # TOKEN provided via DIGITALOCEAN_TOKEN env var
}