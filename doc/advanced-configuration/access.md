The `access` section is used to define **access control lists** which return specific values for specific access classes.

* **Scope:** global
* **Syntax:** each access control list is a key-value pair, where:
    * Key is the name of the ACL,
    * Value is a TOML array of access rules - TOML tables,  whose format is described below.
* **Default:** no default - each access control list needs to be specified explicitly.
* **Example:** see the [ACL examples](#acl-examples) below.

## Access rules

Whenever the ACL is checked to obtain the resulting value for a user, the access rules are traversed one by one until a matching one is found or the list is exhausted (in which case the special value `deny` is returned).

Each of the rules has to contain the following keys (described with full TOML path for reference):

### `access.*.acl`

* **Syntax:** string
* **Example:** `acl = "local"`

The access class defined in the `acl` section. The user is matched against it. The special name `all` is a catch-all value that matches any user. If the class is not defined, the rule does not match (there is no error).

### `access.*.value`

* **Syntax:** string or integer
* **Example:** `value = "allow"`

For rules determining access, the value will be `"allow"` or `"deny"`. For other rules it can be an integer value or a string.

## ACL examples

The following access control lists are already defined in the example configuration file.

### C2S Access

The `c2s` ACL is used to allow/deny the users to establish C2S connections:

```toml
  c2s = [
    {acl = "blocked", value = "deny"},
    {acl = "all", value = "allow"}
  ]
```

It has the following logic:

* if the access class is `blocked`, the returned value is `"deny"`,
* otherwise, the returned value is `"allow"`.

The `blocked` access class can be defined in the `acl` section and match blacklisted users.

For this ACL to take effect, it needs to be referenced in the options of a [C2S listener](listen.md#listenc2saccess).

### C2S Shaper

The `c2s_shaper` ACL is used to determine the shaper used to limit the incoming traffic on C2S connections:

```toml
  c2s_shaper = [
    {acl = "admin", value = "none"},
    {acl = "all", value = "normal"}
  ]
```

It has the following logic:

* if the access class is `admin`, the returned value is `"none"`,
* otherwise, the returned value is `"normal"`.

The `admin` access class can be defined in the `acl` section and match admin users, who will bypass the `normal` shaper.

For this ACL to take effect, it needs to be referenced in the options of a [C2S listener](listen.md#listenc2sshaper).

### S2S Shaper

The `s2s_shaper` ACL is used to determine the shaper used to limit the incoming traffic on C2S connections:

```toml
  s2s_shaper = [
    {acl = "all", value = "fast"}
  ]
```

It assigns the `fast` shaper to all S2S connections.

For this ACL to take effect, it needs to be referenced in the options of a [S2S listener](listen.md#listens2sshaper).

### MUC

The following rules manage the permissions of MUC operations:

```toml
  muc_admin = [
    {acl = "admin", value = "allow"}
  ]

  muc_create = [
    {acl = "local", value = "allow"}
  ]

  muc = [
    {acl = "all", value = "allow"}
  ]
```

They are referenced in the options of the [`mod_muc`](../modules/mod_muc.md) module.

### Registration

This ACL manages the permissions to create new users with `mod_register`.

```toml
  register = [
    {acl = "all", value = "allow"}
  ]
```

It needs to be referenced in the options of `mod_register`.

### MAM permissions

These ACL's set the permissions for MAM operations triggered by IQ stanzas and handled by the [`mod_mam`](../module/mod_mam.md) module.

```toml
  mam_set_prefs = [
    {acl = "all", value = "default"}
  ]

  mam_get_prefs = [
    {acl = "all", value = "default"}
  ]

  mam_lookup_messages = [
    {acl = "all", value = "default"}
  ]
```

They can return `"allow"`, `"deny"` or `"default"`.
The last value uses the default setting for the operation, which is to allow the operation when the sender and recipient JID's are the same.

### MAM shapers

These ACL's limit the rate of MAM operations triggered by IQ stanzas.

```toml
  mam_set_prefs_shaper = [
    {acl = "all", value = "mam_shaper"}
  ]

  mam_get_prefs_shaper = [
    {acl = "all", value = "mam_shaper"}
  ]

  mam_lookup_messages_shaper = [
    {acl = "all", value = "mam_shaper"}
  ]

  mam_set_prefs_global_shaper = [
    {acl = "all", value = "mam_global_shaper"}
  ]

  mam_get_prefs_global_shaper = [
    {acl = "all", value = "mam_global_shaper"}
  ]

  mam_lookup_messages_global_shaper = [
    {acl = "all", value = "mam_global_shaper"}
  ]
```

For each operation there are two ACL's:
- `*_shaper` - limit the number of operations per user connection per second,
- `*_global_shaper` - limit the number of operations per server node per second.

The values returned by the rules (`mam_shaper`, `mam_global_shaper`) are shaper names, which need to be defined in the [`shaper` section](shaper.md#mam-shapers).

### Maximum number of sessions

The `max_user_sessions` ACL is used to determine the maximum number of sessions a user can open.

```toml
  max_user_sessions = [
    {acl = "all", value = 10}
  ]
```

By default all users can open at most 10 concurrent sessions.

### Maximum number of offline messages

The `max_user_offline_messages` ACL is used to determine the maximum number of messages that is stored for a user by `mod_offline`.

```toml
  max_user_offline_messages = [
    {acl = "admin", value = 5000},
    {acl = "all", value = 100}
  ]
```

It has the following logic:

* if the access class is `admin`, the returned value is `5000`,
* otherwise, the returned value is `100`.

This means that the admin users can store 5000 messages offline, while the others can store at most 100.
The `admin` access class can be defined in the `acl` section, e.g.

```toml
  admin = [
    {user = "alice", server = "localhost"}
  ]
```

## Priority: global vs host access lists

By default, both ACL and access elements apply to all domains available on the server.
However, using the `host_config` option, we are able to override selected rules for a particular domain.

```toml
[[host_config]]
  host = "localhost"

  [host_config.access]
    c2s = [
      {acl = "admin", value = "allow"},
      {acl = "all", value = "deny"}
    ]

    register = [
      {acl = "all", value = "deny"}
    ]
```

The global rule has the highest priority, however if the global rule ends with `{allow, all}` the host specific rule is taken into account.

## For developers

To access the ACL functionality, one has to use the `acl:match_rule/3` function.

Given the following ACL:

```toml
  register = [
    {acl = "all", value = "deny"}
  ]
```

One can call:

`acl:match_rule(<<"localhost">>, register, jid:make(<<"p">>, <<"localhost">>, <<>>)).`

Which in our case will return `deny`.
If the rule is not host specific, one can use `global` instead of `<<"localhost">>`.
