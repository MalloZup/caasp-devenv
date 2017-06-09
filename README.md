# CaaSP development environment

This document outlines what's required to set up a CaaSP development environment machine, and how to
develop CaaSP in an efficient way.

You will need to have a working `kubelet` on your machine.

You will also need to clone the following projects where you prefer on your local filesystem:

- [Velum](https://github.com/kubic-project/velum)
- [CaaSP Salt deployment logic](https://github.com/kubic-project/salt)
- [CaaSP container manifests](https://github.com/kubic-project/caasp-container-manifests)
- [Terraform](https://github.com/kubic-project/terraform)

The first three are required to create all the "Administration Dashboard" required services in your
development machine, while the fourth one will spawn VM's that will connect to the "Administration
Dashboard" machine and they will play the role of machines that form part of the Kubernetes cluster.

This setup will allow you to work and make changes to Velum and Salt in a very fast and convenient
way.

## Starting the development environment

```sh
$ VELUM_DIR=~/projects/kubic-project/velum SALT_DIR=~/projects/kubic-project/salt CONTAINER_MANIFESTS_DIR=~/projects/kubic-project/caasp-container-manifests ./start
```

You will need to provide to the `start` script the correct locations of the three projects in your
filesystem using the `VELUM_DIR`, `SALT_DIR` and `CONTAINER_MANIFESTS_DIR` environment variables.

This will use the production kubernetes manifests, perform some modifications to them, and it will
mount your `Velum` directory on the related `Velum` containers, so every change you make locally
to the `Velum` source code will be instantly reflected in the container. Among the rest of the
modifications that are performed automatically to the production manifests, there are some key
changes that make the manifests "development ready", so there's nothing to worry about.

You can also modify your Salt states locally, and they will be reflected on the `salt-master`
container, meaning that after hacking locally on the salt states you can run an orchestration
again or highstates and you will be applying the logic with your latest changes. Nothing is required
to do in between. Hack locally, and run highstates, orchestrations, or whatever you need!

It is also possible to start the development environment in a non interactive way, which basically
means that you won't be asked to do a cleanup before starting, for example; and in general any
interaction will be omitted. This plays nice with CI jobs, for example:

```sh
$ VELUM_DIR=~/projects/kubic-project/velum SALT_DIR=~/projects/kubic-project/salt CONTAINER_MANIFESTS_DIR=~/projects/kubic-project/caasp-container-manifests ./start --non-interactive
```

### Staging based development environment

You can provide the `STAGING` environment variable to the start script, so containers will be pulled
with the `STAGING` image version that you provide. For example, you could execute:

```sh
$ STAGING=staging_a VELUM_DIR=~/projects/kubic-project/velum SALT_DIR=~/projects/kubic-project/salt CONTAINER_MANIFESTS_DIR=~/projects/kubic-project/caasp-container-manifests ./start
```

In this case, for example, MariaDB container would be pulled as: `docker-testing-registry.suse.de/staging_a/sles12/mariadb:10.0`
if the manifest contained `sles12/mariadb:10`.

This allows you to change consistently between development environments based on the current
development repositories, or others based on staging.

If this environment variable is not provided, the pulled images will be the ones referenced in the
`caasp-container-manifests` project (production images).

The supported `STAGING` values can change over time, so that depends on how our build system is
organized on that specific point in time. However, two cases will always apply: leaving it unset
(which means using production images from product), and using `devel`, that will use the current
development branch versions.

```sh
$ STAGING=devel VELUM_DIR=~/projects/kubic-project/velum SALT_DIR=~/projects/kubic-project/salt CONTAINER_MANIFESTS_DIR=~/projects/kubic-project/caasp-container-manifests ./start
```

This will effectively use the `devel` version of the containers.

## Accessing your shiny development environment

Once that you have started the development environment, you will be able to point your preferred
browser to `http://localhost:3000` and you should be greeted with the CaaSP welcoming page.

## Hacking on Velum

In general, you can check that if you modify the welcome view, and refresh the welcoming page on
your browser it will be updated instantly.

But in general we use `rspec` and `rubocop` to do the heavy lifting while developing, so, first we
will need to create the testing environment database:

```sh
$ docker exec -it $(docker ps | grep velum-dashboard | awk '{print $1}') entrypoint.sh bash -c "RAILS_ENV=test rake db:setup"
```

You will need to do this only once (only once every time you recreate the development environment).

After this, you will be able to go to the typical cycle of hacking code, and running tests, like
this:

```sh
$ docker exec -it $(docker ps | grep velum-dashboard | awk '{print $1}') entrypoint.sh bash -c "RAILS_ENV=test rspec"
$ docker exec -it $(docker ps | grep velum-dashboard | awk '{print $1}') entrypoint.sh bash -c "RAILS_ENV=test rubocop".
```

## Hacking on Salt

This also applies to salt, so you can modify salt related code, and run orchestrations, or
highstates on certain machines.

## Spawning test workers

We have created what we call the "Administration Dashboard". However we need to spawn workers.
They are a different thing, as they really need to be VM's in this case. As we said before, we will
use `terraform` for this.

All instructions that follow are executed from within the root path of the `terraform` project.

We will need to provide at least one environment variable: `SKIP_DASHBOARD`. This will instruct
the provisioning script to not create another VM for the dashboard, and will use some logic to
point the VM's to your development machine. You can also instruct yourself the reachable IP address
that you want the script to use instead of the default one using `DASHBOARD_HOST` environment
variable.

```sh
$ SKIP_DASHBOARD=1 MINIONS_SIZE=2 contrib/libvirt/k8s-libvirt.sh apply
```

By default, if you use `SKIP_DASHBOARD=1`, the `k8s-libvirt.sh` script will find the IP address of
your default interface, which will suffice in most cases and is a sane default. It will do this:

```sh
default_interface=$(awk '$2 == 00000000 { print $1 }' /proc/net/route)
ip_address=$(ip addr show $default_interface | awk '$1 == "inet" {print $2}' | cut -f1 -d/)
```

And it will use `DASHBOARD_HOST=$ip_address`. However, if you want to override this default, you
can just pass `DASHBOARD_HOST` with the IP address you want the VM's to point to instead. Please
note, that in this environment what the VM's can resolve is very limited, so is better to use
IP addresses instead of hostnames of fqdns.

## Tips and tricks

### Following salt events as they come

This command will help you monitor salt events as they come. Be advised this command *won't* print
older events.

```sh
$ docker exec -it $(docker ps | grep salt-master | awk '{print $1}') salt-run state.event pretty=True
```

### Cleaning up

You will need to clean the terraform side of things (from within the terraform root directory):

```sh
$ contrib/libvirt/k8s-libvirt.sh destroy
```

And then, you can also use this development environment to clean all the containers on your machine:

```sh
$ ./cleanup
```

## Licensing

CaaSP development environment is licensed under the Apache License, Version 2.0. See
[LICENSE](https://github.com/kubic-project/velum/blob/master/LICENSE) for the
full license text.
