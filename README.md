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

## Usage

Organization:

    cloud org list
    cloud org show 1234cafe...

Projects:

    cloud project list
    cloud project show 1234cafe...

IP whitelists:

    cloud whitelist -p 1234cafe... list
    cloud whitelist -p 1234cafe... show 0.0.0.0/0
    cloud whitelist -p 1234cafe... add 0.0.0.0

Database users:

    cloud dbuser -p 1234cafe... list
    cloud dbuser -p 1234cafe... show UserName
    cloud dbuser -p 1234cafe... create UserName Password

Deployments:

    cloud cluster -p 1234cafe... list
    cloud cluster -p 1234cafe... show ClusterName

## License

MIT
