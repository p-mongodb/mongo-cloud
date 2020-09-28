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

## Usage

Organization:

    mongo-cloud org list
    mongo-cloud org show 1234cafe...

Projects:

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

Deployments:

    mongo-cloud cluster -p 1234cafe... list
    mongo-cloud cluster -p 1234cafe... show ClusterName

## License

MIT
