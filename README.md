# jx3-kind

Jenkins X 3.x GitOps repository using Docker/Kind to create a kubernetes cluster, github for the git and container registry and local secrets
      

## Prerequisites 

Make sure you have installed and are running [Docker Desktop](https://www.docker.com/products/docker-desktop)

## Running

You need to setup some environment variables first...

```bash
# if you are on a mac 
export PLATFORM=darwin

# or windows...
export PLATFORM=windows 

# we need your machines local IP address and the gateway & subnet for making the docker network:
export IP="192.168.1.202"
export GATEWAY="192.168.1.254"
export SUBNET="192.168.1.0/16"
```

once those are setup you can create a kind cluster with gitea and the Jenkins X Git Operator installed via:

```bash
./kind.sh create 
```

to tear it all down again

```bash
./kind.sh destroy 
```
