## The purpose of sender-jid-from-mam-message.escript

This script may be used as a part of migration from MongooseIM 3.3.0 (or older).
It is able to extract a groupchat message's sender's JID from an XML payload.
This piece of information is essential for GDPR commands (retrieve data and remove user) to work properly, as without it the operations on MAM MUC data in DB would be extremely inefficient.

Please consult "3.3.0 to..." migration guide for details.
DB-specific sections describe where the payloads are stored and what you should do with the extracted JID.

## Requirements

This script may be executed in every \*nix environment which has OTP 19.0 (or newer) installed and `escript` executable is in `PATH`.

It doesn't depend on any MongooseIM code or library, so it may be used as a standalone file.

## How to use?

`sender-jid-from-mam-message.escript (eterm | xml)

The only parameter required by the script is the input format.
If your MongooseIM by default uses "eterm" message format in MAM DB.
It means you should use this option if:

* You haven't set `db_message_format` option for MAM at all.
* `db_message_format` is set to `mam_message_compressed_eterm` or `mam_message_eterm`

You should use `xml` option if `db_message_format` is set to `mam_message_xml`.

Once started, script will run in an infinite loop (until killed or interrupted), expecting a stream of inputs.
For every provided payload, a JID will be returned immediately.
All communication with the script is done via `stdio`.

### Input format

For both `eterm` and `xml` mode, the script expects an input in a very similar format.
The high-level overview is:

```
LENGTH\nPAYLOAD
```

* `LENGTH` is a `PAYLOAD` length in bytes
** if data retrieved from a DBMS is an Unicode string, `LENGTH` is equal to the number of bytes used to encode this string
* `PAYLOAD` is a sequence of bytes
** if a DBMS returns binary data encoded as hex, then it has to be decoded to raw bytes
* `LENGTH` and `PAYLOAD` are separated with newline character (ASCII code 10 / 0x0a)

### Output format

The script output format is very similar to the input:

```
LENGTH\nJID
```

* LENGTH is a number of bytes in `JID`
* JID is a sequence of bytes, which encode an Unicode string
* `LENGTH` and `PAYLOAD` are separated with newline character (ASCII code 10 / 0x0a)

## Examples

`tools/migration` folder contains two files: `sender-jid-from-mam-message.example.eterm` and `sender-jid-from-mam-message.example.xml`.
They are input samples for the script and may be used as a reference for the script usage.

You may test them with running:

* `tools/migration/sender-jid-from-mam-message.escript eterm < sender-jid-from-mam-message.example.eterm > out`
* `tools/migration/sender-jid-from-mam-message.escript xml < sender-jid-from-mam-message.example.xml > out`

In both cases `out` file should have the following content:

```
37
gżegżółka@brzęczyszczykiewicz.pl
```

## Debug

If an environment variable `DEBUG` is set to `1`, the script will store error messages in a file `/tmp/script-debug`.

