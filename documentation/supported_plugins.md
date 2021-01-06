# Supported plugins

The following plugins are supported and maintained by Bolt. Supported plugins
are shipped with Bolt packages and do not need to be installed separately.

## Reference plugins

Reference plugins fetch data from an external source and store it in a static
data object. You can use reference plugins in configuration files, inventory
files, and plans.

| Plugin | Description | Documentation |
| --- | --- | --- |
| `aws_inventory` | Generate targets from Amazon Web Services EC2 instances. | [aws_inventory](https://forge.puppet.com/puppetlabs/aws_inventory) |
| `azure_inventory` | Generate targets from Azure VMs and VM scale sets. | [azure_inventory](https://forge.puppet.com/puppetlabs/azure_inventory) |
| `env_var` | Read values stored in environment variables. | [env_var](#env-var) |
| `gcloud_inventory` | Generate targets from Google Cloud compute engine instances. | [gcloud_inventory](https://forge.puppet.com/puppetlabs/gcloud_inventory) |
| `pkcs7` | Decrypt ciphertext. | [pkcs7](https://forge.puppet.com/puppetlabs/pkcs7) |
| `prompt` | Prompt the user for a sensitive value. | [prompt](#prompt) |
| `puppetdb` | Query PuppetDB for a group of targets. | [puppetdb](#puppetdb) |
| `puppet_connect_data` | Pass target connection data over to Puppet Connect | [puppet_connect_data](#puppet_connect_data)
| `task` | Run a task as a plugin. | [task](#task) |
| `terraform` | Generate targets from local and remote Terraform state files. | [terraform](https://forge.puppet.com/puppetlabs/terraform) |
| `vault` | Access secrets from a Key/Value engine on a Hashicorp Vault server. | [vault](https://forge.puppet.com/puppetlabs/vault) |
| `yaml` | Compose multiple YAML files into a single file. | [yaml](#yaml) |

## Secret plugins

Use secret plugins to create keys for encryption and decryption, to encrypt
plaintext, or to decrypt ciphertext. Secret plugins are used by Bolt's `secret`
command.

| Plugin | Description | Documentation |
| --- | --- | --- |
| `pkcs7` | Generate key pairs, encrypt plaintext, and decrypt ciphertext. | [pkcs7](https://forge.puppet.com/puppetlabs/pkcs7) |

## Puppet library plugins

Puppet library plugins ensure that the Puppet library is installed on a target
when a plan calls the `apply_prep` function.

| Plugin | Description | Documentation |
| --- | --- | --- |
| `puppet_agent` | Install Puppet libraries on target nodes when a plan calls `apply_prep`. | [puppet_agent](https://forge.puppet.com/puppetlabs/puppet_agent) |

## Built-in plugins

The following plugins are built into Bolt and are not available in modules.

### `env_var`

The `env_var` plugin allows users to read values stored in environment variables
and load them into an inventory or configuration file.

#### Parameters

The following parameters are available to the `env_var` plugin:

| Parameter | Description | Type | Default |
| --- | ----------- | ---- | ------- |
| `var` | **Required.** The name of the environment variable to read from. | `String` | None |
| `default` | A value to use if the environment variable `var` isn't set. | `String` | None |
| `optional` | Unless `true`, `env_var` raises an error when the environment variable `var` does not exist.  When `optional` is `true` and `var` does not exist, env_var returns `nil`. | `Boolean` | `false` |

#### Example usage

Looking up a value from an environment variable in an inventory file:

```yaml
targets:
  - target1.example.com
config:
  ssh:
    user: bolt
    password:
      _plugin: env_var
      var: BOLT_PASSWORD
```

### `prompt`

The `prompt` plugin allows users to interactively enter sensitive configuration
information on the CLI instead of storing that data in the inventory file. Data
is looked up when the value is needed for the target. Once the value has been
stored, it is re-used for the rest of the Bolt run.

#### Parameters

The following parameter is available to the `prompt` plugin:

| Parameter | Description | Type | Default |
| --- | --- | --- | --- |
| `message` | **Required.** The text to show when prompting the user. | `String` | None |

#### Example usage

Prompting for a password in an inventory file:

```yaml
targets:
  - target1.example.com
config:
  ssh:
    password:
      _plugin: prompt
      message: Enter your SSH password
```

### `puppetdb`

The `puppetdb` plugin queries PuppetDB for a group of targets. 

If you require target-specific configuration, you can use the `puppetdb` plugin
to look up configuration values for the `alias`, `config`, `facts`, `features`,
`name`, `uri` and `vars` inventory options for each target. Set these values in
the `target_mapping` field. The fact look up values can be either `certname` to
reference the `[certname]` of the target, or a [PQL dot
notation](https://puppet.com/docs/puppetdb/latest/api/query/v4/ast.html#dot-notation)
facts string such as `facts.os.family` to reference a fact value. Dot notation
is required for both structured and unstructured facts.

#### Parameters

The following parameters are available to the `puppetdb` plugin:

| Parameter | Description | Type | Default |
| --- | ----------- | ---- | ------- |
| `query` | **Required.** A string containing a [PQL query](https://puppet.com/docs/puppetdb/latest/api/query/v4/pql.html) or an array containing a [PuppetDB AST format query](https://puppet.com/docs/puppetdb/latest/api/query/v4/ast.html). | `String` | None |
| `target_mapping` | **Required.** A hash of target attributes (`name`, `uri`, `config`) to populate with fact lookup values. | `Hash` | None |

> **Note:** If neither `name` nor `uri` is specified in `target_mapping`, then
> `uri` is set to `certname`.

#### Available fact paths

The following values/patterns are available to use for looking up facts in the
`target_mapping` field:

| Key | Description |
| --- | ----------- |
| `certname` | The certname of the node returned from PuppetDB. This is short hand for doing: `facts.trusted.certname`. |
| `facts.*` | [PQL dot notation](https://puppet.com/docs/puppetdb/latest/api/query/v4/ast.html#dot-notation) facts string such as `facts.os.family` to reference fact value. Dot notation is required for both structured and unstructured facts. |

#### Example usage

Look up targets with the fact `osfamily: RedHat` and the following configuration
values:
 * The alias with the fact `hostname`
 * The name with the fact `certname`
 * A target fact called `custom_fact` with the `custom_fact` from PuppetDB
 * A feature from the fact `custom_feature`
 * The SSH hostname with the fact `networking.interfaces.en0.ipaddress`
 * The puppetversion variable from the fact `puppetversion`

```yaml
targets:
  - _plugin: puppetdb
    query: "inventory[certname] { facts.osfamily = 'RedHat' }"
    target_mapping:
      alias: facts.hostname
      name: certname
      facts:
        custom_fact: facts.custom_fact
      features:
        - facts.custom_feature
      config:
        ssh:
          host: facts.networking.interfaces.en0.ipaddress
      vars:
        puppetversion: facts.puppetversion
```

### `task`

The `task` plugin lets Bolt run a task as a plugin and extracts the `value` key
from the task output to use as the plugin value. Plugin tasks run on the
`localhost` target without access to any configuration defined in an inventory
file, but with access to any parameters that you've configured.

For example, you could run a `task` plugin that collects target names from a
JSON file and interpolates them into a `target` array in your inventory file.

#### Parameters

The following parameters are available to the `task` plugin:

| Key | Description | Type | Default |
| --- | ----------- | ---- | ------- |
| `task` | **Required.** The name of the task to run. | `String` | None |
| `parameters` | The parameters to pass to the task. | `Hash` | None |

#### Example usage

Loading targets with a `my_json_file::targets` task and a password with a
`my_db::secret_lookup` task:

```yaml
targets:
  - _plugin: task
    task: my_json_file::targets
    parameters:
      file: /etc/targets/data.json
      environment: production
      app: my_app
config:
  ssh:
    password:
      _plugin: task
      task: my_db::secret_lookup
      parameters:
        key: ssh_password
```

### `puppet_connect_data`

The `puppet_connect_data` plugin lets you pass-in target connection
information as key-value data to Puppet Connect. You can use it to
specify auto-loaded SSH config (e.g. users and private keys) or secrets
(e.g. WinRM passwords).

Puppet Connect securely stores your target connection information in a
Postgres database. All secrets are stored in encrypted format. See
the [stored connection data](#stored-connection-data) section for more
details.

**Note:** Only the SSH and WinRM transports are supported in Puppet
Connect. Also, this is an _experimental_ feature.

#### Parameters

The following parameter is available to the `puppet_connect_data` plugin:

| Parameter | Description | Type | Default |
| --- | --- | --- | --- |
| `key` | **Required.** The key that contains the value. If the key is not specified in the data, then its value is resolved to `nil`. A `nil`-resolved value is equivalent to not specified _if_ the resolved value represents a transport's config. See the examples below for more clarification. | `String` | None |

#### Example usage

```yaml
targets:
  - target1.example.com
    config:
      ssh:
        user:
          _plugin: puppet_connect_data
          key: ssh_user
        password:
          _plugin: puppet_connect_data
          key: ssh_password
```

Here, if the specified data is `{"ssh_user": "foo_user", "ssh_password": "foo_password"}`, then
the `user` and `password` keys are resolved to `foo_user` and `foo_password`.
Conversely, if the specified data is `{}`, then the `user` and `password`
keys are resolved to `nil`. Since the `user` and `password` keys are part of
the SSH transport's config, Bolt will delete these keys from the parsed config.
Thus when data is `{}`, the above example will be parsed as

```yaml
targets:
  - target1.example.com
    config:
      ssh: {}
```

> If you run Bolt on a target with the above config, then Bolt will auto-load
the target's SSH config (default behavior).

#### puppet_connect_data.yaml

If a `puppet_connect_data.yaml` file exists in your project root, then the
`puppet_connect_data` plugin will parse its data from this file. Below is an
example of a valid `puppet_connect_data.yaml` file:

```yaml
ssh_user: foo_user
ssh_password: foo_password
```

Here, the parsed data is `{"ssh_user": "foo_user", "ssh_password": "foo_password"}`.

In the above example, `ssh_password` is specified as plain-text. For better security,
you can specify plugin-reference values for your keys. Take a look at the following
example:

```yaml
ssh_user: foo_user
ssh_password:
  _plugin: env_var
  var: SSH_PASSWORD
```

Here, the `ssh_password` is resolved by the `env_var` plugin.

**Note:** As of this writing, `puppet_connect_data` does _not_ cache resolved plugin
reference values. Thus, given a key that resolves to a plugin reference, if that same
key's referenced multiple times in the inventory file, then the plugin reference is
re-evaluated each time. For example, given the above `puppet_connect_data.yaml` file,
an inventory like:

```
targets:
  - target1.example.com
    config:
      ssh:
        user:
          _plugin: puppet_connect_data
          key: ssh_user
        password:
          _plugin: puppet_connect_data
          key: ssh_password
  - target2.example.com
    config:
      ssh:
        user:
          _plugin: puppet_connect_data
          key: ssh_user
        password:
          _plugin: puppet_connect_data
          key: ssh_password
```

will result in the `ssh_password` reference being evaluated _twice_ (once for
the first target and once for the second).

We plan on adding caching support in a later iteration of the plugin. Please
file an issue if you'd like us to expedite this process.

**Note:** You do not have to specify auto-loaded, `puppet_connect_data`-referenced
SSH config in your `puppet_connect_data.yaml` file. The `puppet_connect_data` plugin
resolves all unspecified keys to `nil`, which tells Bolt to remove the corresponding
config keys from the target's transport config (meaning SSH config will be auto-loaded
if that was the previous, pre-`puppet_connect_data` plugin behavior).

#### Stored connection data

The table below documents the target connection data stored by Puppet Connect.
Secrets are bolded.

##### SSH

* user
* port
* connect-timeout
* run-as
* tmpdir
* tty
* hostname
* **password**
* **private-key.key-data**
* **sudo-password**

##### WinRM

* user
* port
* connect-timeout
* tmpdir
* extensions
* hostname
* **password**
