# MongoDB Cloud API Client

This is a Ruby client and a command-line tool for the [MongoDB Atlas API
](https://docs.atlas.mongodb.com/api/). Other Cloud APIs may be added in the
future based on demand.

This tool is an alternative to [mongocli](https://github.com/mongodb/mongocli).
It was started to address the following goals:

- Support for actions that mongocli did not implement (such as Atlas
organization management).
- Easier to use command line argument/option structure.
- A Ruby API client consumable by other libraries/programs.

## Configuration

Credentials can be given as top-level command-line options:

    cloud -u $USERNAME -p $PASSWORD ...

They can also be supplied via mongocli-compatible environment variables:

    export MCLI_PUBLIC_API_KEY=$USERNAME MCLI_PRIVATE_API_KEY=$PASSWORD

To use atlas-dev, set `MCLI_OPS_MANAGER_URL`:

    export MCLI_OPS_MANAGER_URL=https://cloud-dev.mongodb.com

## General Operation

The [Atlas API](https://docs.atlas.mongodb.com/reference/api-resources/)
generally requires multiple parameters to identify any given resource,
and there is no consistent scheme that is used for resource identification.
For example, to operate on clusters one must supply a project id and a
cluster name.

mongo-cloud by default assumes that all resources specified by the user are
identified by their id. For example, to view a cluster, one might issue:

    mongo-cloud cluster -p PROJECT-ID -c CLUSTER-ID show

The cluster can also be identified by its name, for compatibility with
other tools:

    mongo-cloud cluster -p PROJECT-ID --cluster-name CLUSTER-NAME show

For convenience, whenever a resource identifier is needed, mongo-cloud
accepts both the id and the customary identifier used by Atlas API for the
resource in question. For clusters this means that cluster name can be used
as the parameter to the `-c` argument:

    mongo-cloud cluster -p PROJECT-ID -c CLUSTER-NAME show

Note that mongo-cloud will first attempt to interpret each identifier as the
id even if the underlying API endpoint specifies a different field such as
the name.

Since providing multiple identifiers is in most cases redundant, mongo-cloud
transparently stores mappings of both id mappings and resource parent
mappings when resources are retrieved. For example, when retrieving a list
of clusters in a project, mongo-cloud stores the mapping from cluster ids to
cluster names and the mapping from cluster ids to project ids for each cluster.
Subsequently a cluster can be viewed by specifying only the cluster id:

    mongo-cloud cluster -p PROJECT-ID list
    mongo-cloud cluster -c CLUSTER-NAME show

## Usage

Organization:

    mongo-cloud org list
    mongo-cloud org show 1234cafe...

Projects:

    mongo-cloud project create --org ORG-ID --name PROJECT-NAME
    mongo-cloud project list
    mongo-cloud project show 1234cafe...

IP whitelists:

    mongo-cloud whitelist -p 1234cafe... list
    mongo-cloud whitelist -p 1234cafe... show 0.0.0.0/0
    mongo-cloud whitelist -p 1234cafe... add 0.0.0.0

Database users:

    mongo-cloud dbuser -p 1234cafe... list
    mongo-cloud dbuser -p 1234cafe... show UserName
    mongo-cloud dbuser -p 1234cafe... create UserName Password

Clusters:

    mongo-cloud cluster -p PROJECT-ID create --name NAME --config YAML-CONFIG
    mongo-cloud cluster -p PROJECT-ID list
    mongo-cloud cluster -p PROJECT-ID show ClusterName
    mongo-cloud cluster [-p PROJECT-ID] -c CLUSTER-ID reboot

## License

MIT
