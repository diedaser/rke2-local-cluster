terraform {
  required_version = ">= 1.8"

  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 3.4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.9.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.6.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.3.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.3.0"
    }
    # Provider major version tracks the Rancher minor version (v15 = Rancher 2.15).
    rancher2 = {
      source  = "rancher/rancher2"
      version = "~> 15.1.0"
    }
  }
}
